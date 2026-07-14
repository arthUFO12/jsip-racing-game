open! Core

(* Gameplay tuning. Provisional values assuming the server's ~30 ticks/s;
   once a config module exists these belong there. *)
let bridge_telegraph_ticks = 30 (* ~1s shaking before it falls *)
let bridge_collapsed_ticks = 300 (* ~10s gap before auto-rebuild *)
let gate_telegraph_ticks = 45 (* ~1.5s portcullis descending *)
let gate_closed_ticks = 240 (* ~8s shut *)
let stalactite_telegraph_ticks = 24 (* ~0.8s falling *)
let stalactite_debris_ticks = 150 (* ~5s rubble *)
let ice_melt_ticks = 240 (* ~8s slick *)
let ice_radius = 1.5 (* world units; footprint via [Cell.in_radius] *)

type t = { features : Feature.t Feature_id.Map.t }
[@@deriving sexp_of, bin_io]

(* Hand-written rather than derived so a server state and a client
   replica compare equal however their maps were built up. *)
let equal a b = Map.equal Feature.equal a.features b.features

let create map =
  let features =
    Game_map.initial_features map
    |> List.map ~f:(fun (feature : Feature.t) -> feature.id, feature)
    |> Feature_id.Map.of_alist_exn
  in
  { features }
;;

module Update = struct
  type t =
    | Set of Feature.t
    | Removed of Feature_id.t
  [@@deriving sexp, bin_io, compare, equal]
end

(* Composed queries scan every feature naively — a map has only a handful.
   A [Cell.t -> Feature.t list] index rebuilt per update would make these
   O(1); measure before bothering. *)
let features_covering t cell =
  Map.data t.features
  |> List.filter ~f:(fun (feature : Feature.t) ->
    List.mem feature.cells cell ~equal:Cell.equal)
;;

(* Authored features never overlap (validated at load) and a spawned ice
   patch never overrides, so at most one covering feature has an
   override. *)
let surface_at_cell t ~map cell =
  match List.find_map (features_covering t cell) ~f:Feature.surface_override with
  | Some surface -> surface
  | None -> Game_map.base_surface_at map cell
;;

let surface_at t ~map v = surface_at_cell t ~map (Game_map.cell_at map v)
let is_blocked t ~map cell = Surface.is_solid (surface_at_cell t ~map cell)

let is_gap t ~map:(_ : Game_map.t) cell =
  List.exists (features_covering t cell) ~f:Feature.is_gap
;;

let traction_at t ~map v =
  features_covering t (Game_map.cell_at map v)
  |> List.fold ~init:1.0 ~f:(fun traction feature ->
    traction *. Feature.traction_multiplier feature)
;;

let update_feature t ~id ~f =
  match Map.find t.features id with
  | None -> Or_error.error_s [%message "no such feature" (id : Feature_id.t)]
  | Some feature ->
    let%map.Or_error feature' = f feature in
    ( { features = Map.set t.features ~key:id ~data:feature' }
    , [ Update.Set feature' ] )
;;

let kind_mismatch feature ~action =
  Or_error.error_s
    [%message
      "action does not match feature kind"
        (Feature.kind feature : Feature.Kind.t)
        (action : Track_action.t)]
;;

let apply_action t ~map ~(action : Track_action.t) ~now =
  match action with
  | Collapse_bridge id ->
    update_feature t ~id ~f:(fun feature ->
      match feature.payload with
      | Bridge { phase = Intact } ->
        Ok
          { feature with
            payload =
              Bridge
                { phase =
                    Collapsing { falls_at = Tick.add now bridge_telegraph_ticks }
                }
          }
      | Bridge { phase = (Collapsing _ | Collapsed _) as phase } ->
        Or_error.error_s
          [%message
            "bridge is not intact"
              (id : Feature_id.t)
              (phase : Feature.Bridge.Phase.t)]
      | Gate (_ : Feature.Gate.t)
      | Stalactite (_ : Feature.Stalactite.t)
      | Ice_patch (_ : Feature.Ice_patch.t) -> kind_mismatch feature ~action)
  | Close_gate id ->
    update_feature t ~id ~f:(fun feature ->
      match feature.payload with
      | Gate { phase = Open } ->
        Ok
          { feature with
            payload =
              Gate { phase = Closing { shut_at = Tick.add now gate_telegraph_ticks } }
          }
      | Gate { phase = (Closing _ | Closed _) as phase } ->
        Or_error.error_s
          [%message
            "gate is not open" (id : Feature_id.t) (phase : Feature.Gate.Phase.t)]
      | Bridge (_ : Feature.Bridge.t)
      | Stalactite (_ : Feature.Stalactite.t)
      | Ice_patch (_ : Feature.Ice_patch.t) -> kind_mismatch feature ~action)
  | Drop_stalactite id ->
    update_feature t ~id ~f:(fun feature ->
      match feature.payload with
      | Stalactite { phase = Hanging } ->
        Ok
          { feature with
            payload =
              Stalactite
                { phase =
                    Falling { lands_at = Tick.add now stalactite_telegraph_ticks }
                }
          }
      | Stalactite { phase = (Falling _ | Debris _) as phase } ->
        Or_error.error_s
          [%message
            "stalactite is not hanging"
              (id : Feature_id.t)
              (phase : Feature.Stalactite.Phase.t)]
      | Bridge (_ : Feature.Bridge.t)
      | Gate (_ : Feature.Gate.t)
      | Ice_patch (_ : Feature.Ice_patch.t) -> kind_mismatch feature ~action)
  | Place_ice center ->
    let cells =
      Cell.in_radius ~center ~radius:ice_radius ~cell_size:(Game_map.cell_size map)
    in
    let not_open_road =
      List.filter cells ~f:(fun cell ->
        match surface_at_cell t ~map cell with
        | Road -> is_gap t ~map cell
        | Wall | Trees -> true)
    in
    (match cells with
     | [] -> Or_error.error_s [%message "ice footprint is empty" (center : Vec2.t)]
     | _ :: _ ->
       (match not_open_road with
        | _ :: _ ->
          Or_error.error_s
            [%message
              "ice must land on open road"
                (center : Vec2.t)
                (not_open_road : Cell.t list)]
        | [] ->
          let id =
            Feature_id.of_int
              (1
               + (Map.max_elt t.features
                  |> Option.value_map ~default:(-1) ~f:(fun (id, _) ->
                    Feature_id.to_int id)))
          in
          (* Overlapping an existing ice patch is allowed: traction
             multipliers stack. *)
          let feature =
            { Feature.id
            ; cells
            ; payload = Ice_patch { melts_at = Tick.add now ice_melt_ticks }
            }
          in
          Ok
            ( { features = Map.set t.features ~key:id ~data:feature }
            , [ Update.Set feature ] )))
;;

(* The server calls this every tick, so each feature advances AT MOST one
   phase per call. The next expiry is anchored on the OLD expiry rather
   than [now], so even a late call yields the same deterministic
   schedule. *)
let tick t ~now =
  let t, rev_updates =
    Map.fold
      t.features
      ~init:(t, [])
      ~f:(fun ~key:id ~data:(feature : Feature.t) ((t, rev_updates) as acc) ->
        let expired expiry = Tick.( <= ) expiry now in
        let set payload =
          let feature = { feature with payload } in
          ( { features = Map.set t.features ~key:id ~data:feature }
          , Update.Set feature :: rev_updates )
        in
        match feature.payload with
        | Bridge { phase = Intact }
        | Gate { phase = Open }
        | Stalactite { phase = Hanging } -> acc
        | Bridge { phase = Collapsing { falls_at } } ->
          (match expired falls_at with
           | false -> acc
           | true ->
             set
               (Bridge
                  { phase =
                      Collapsed
                        { rebuilt_at = Tick.add falls_at bridge_collapsed_ticks }
                  }))
        | Bridge { phase = Collapsed { rebuilt_at } } ->
          (match expired rebuilt_at with
           | false -> acc
           | true -> set (Bridge { phase = Intact }))
        | Gate { phase = Closing { shut_at } } ->
          (match expired shut_at with
           | false -> acc
           | true ->
             set
               (Gate
                  { phase =
                      Closed { reopens_at = Tick.add shut_at gate_closed_ticks }
                  }))
        | Gate { phase = Closed { reopens_at } } ->
          (match expired reopens_at with
           | false -> acc
           | true -> set (Gate { phase = Open }))
        | Stalactite { phase = Falling { lands_at } } ->
          (match expired lands_at with
           | false -> acc
           | true ->
             set
               (Stalactite
                  { phase =
                      Debris
                        { cleared_at = Tick.add lands_at stalactite_debris_ticks }
                  }))
        | Stalactite { phase = Debris { cleared_at } } ->
          (match expired cleared_at with
           | false -> acc
           | true -> set (Stalactite { phase = Hanging }))
        | Ice_patch { melts_at } ->
          (match expired melts_at with
           | false -> acc
           | true ->
             ( { features = Map.remove t.features id }
             , Update.Removed id :: rev_updates )))
  in
  (* [Map.fold] visits ids in ascending order; the [rev] restores that
     order for the updates. *)
  t, List.rev rev_updates
;;

let melt_ice t ~id =
  match Map.find t.features id with
  | None -> Or_error.error_s [%message "no such feature" (id : Feature_id.t)]
  | Some feature ->
    (match feature.payload with
     | Ice_patch (_ : Feature.Ice_patch.t) ->
       Ok ({ features = Map.remove t.features id }, [ Update.Removed id ])
     | Bridge (_ : Feature.Bridge.t)
     | Gate (_ : Feature.Gate.t)
     | Stalactite (_ : Feature.Stalactite.t) ->
       Or_error.error_s
         [%message
           "feature is not an ice patch"
             (id : Feature_id.t)
             (Feature.kind feature : Feature.Kind.t)])
;;

let apply_update t (update : Update.t) =
  match update with
  | Set feature ->
    { features = Map.set t.features ~key:feature.id ~data:feature }
  | Removed id -> { features = Map.remove t.features id }
;;

let feature t id = Map.find t.features id
let features t = Map.data t.features

(* "Footprint intersects the disc" is approximated by testing each
   footprint cell's CENTER against [radius]. *)
let features_near t ~map ~center ~radius =
  let cell_size = Game_map.cell_size map in
  Map.data t.features
  |> List.filter ~f:(fun (feature : Feature.t) ->
    List.exists feature.cells ~f:(fun cell ->
      Float.( <= ) (Vec2.distance (Cell.center cell ~cell_size) center) radius))
;;

module Viewport = struct
  type t =
    { origin : Cell.t
    ; surfaces : Surface.t array array
    ; environments : Environment.t array array
    ; features : Feature.t list
    ; is_dark : bool
    }
  [@@deriving sexp_of, bin_io]
end

let viewport t ~map ~center ~half_extent_cells =
  let center_cell = Game_map.cell_at map center in
  let origin =
    { Cell.col = center_cell.col - half_extent_cells
    ; row = center_cell.row - half_extent_cells
    }
  in
  let size = (2 * half_extent_cells) + 1 in
  let cell_at ~r ~c = { Cell.col = origin.col + c; row = origin.row + r } in
  let grid ~f =
    Array.init size ~f:(fun r -> Array.init size ~f:(fun c -> f (cell_at ~r ~c)))
  in
  let in_slice ({ col; row } : Cell.t) =
    col >= origin.col
    && col < origin.col + size
    && row >= origin.row
    && row < origin.row + size
  in
  { Viewport.origin
  ; surfaces = grid ~f:(surface_at_cell t ~map)
  ; environments = grid ~f:(Game_map.environment_at map)
  ; features =
      Map.data t.features
      |> List.filter ~f:(fun (feature : Feature.t) ->
        List.exists feature.cells ~f:in_slice)
  ; is_dark = Environment.is_dark (Game_map.environment_at map center_cell)
  }
;;
