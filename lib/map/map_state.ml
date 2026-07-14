open! Core
open Racing_types

type t = { features : Feature.t Feature_id.Map.t }
[@@deriving sexp_of, bin_io]

(* Hand-written rather than derived so a server state and a client replica
   compare equal however their maps were built up. *)
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

(* Expected shape: look the target feature up by id; check the action matches
   its kind and that it is in its rest phase ([Intact] / [Open] / [Hanging]);
   move it to its telegraph phase with an expiry of [now] + the relevant
   duration constant. [Place_ice] instead validates that [Cell.in_radius]
   around the target is all open road ([Map_state.surface_at] = [Road], no
   gap), allocates a fresh [Feature_id.t] (one past the max id in
   [t.features]), and inserts the patch. Every path returns the new [t] plus
   [Set]s for what changed; failures are [Or_error.error_s] with the
   id/action for context. *)
let apply_action
  (_ : t)
  ~map:(_ : Game_map.t)
  ~action:(_ : Track_action.t)
  ~now:(_ : Tick.t)
  =
  failwith "TODO: implement Map_state.apply_action"
;;

(* Expected shape: fold over [t.features]; any phase whose expiry is [<= now]
   advances ([Collapsing -> Collapsed of { rebuilt_at }],
   [Collapsed -> Intact], [Closing -> Closed of { reopens_at }],
   [Closed -> Open], [Falling -> Debris of { cleared_at }],
   [Debris -> Hanging]); an [Ice_patch] past [melts_at] is dropped with
   [Removed]. Durations are tick-count constants defined at the top of this
   file until a config module exists. *)
let tick (_ : t) ~now:(_ : Tick.t) =
  failwith "TODO: implement Map_state.tick"
;;

(* Expected shape: [Removed id] if the id is a live [Ice_patch]; an error
   naming the id otherwise. *)
let melt_ice (_ : t) ~id:(_ : Feature_id.t) =
  failwith "TODO: implement Map_state.melt_ice"
;;

let apply_update t (update : Update.t) =
  match update with
  | Set feature ->
    { features = Map.set t.features ~key:feature.id ~data:feature }
  | Removed id -> { features = Map.remove t.features id }
;;

(* Expected shape for the composed queries: find the features whose [cells]
   contain the queried cell; apply [Feature.surface_override] (solid-most
   wins — authored features never overlap, validated at load, so ties only
   involve a spawned ice patch, which never overrides); [is_gap] and
   [traction_at] similarly consult [Feature.is_gap] /
   [Feature.traction_multiplier]. A [Cell.t -> Feature.t list] index built
   once per update would make these O(1); start with the naive scan and
   measure before bothering. *)
let surface_at (_ : t) ~map:(_ : Game_map.t) (_ : Position.t) =
  failwith "TODO: implement Map_state.surface_at"
;;

let is_blocked (_ : t) ~map:(_ : Game_map.t) (_ : Cell.t) =
  failwith "TODO: implement Map_state.is_blocked"
;;

let is_gap (_ : t) ~map:(_ : Game_map.t) (_ : Cell.t) =
  failwith "TODO: implement Map_state.is_gap"
;;

let traction_at (_ : t) ~map:(_ : Game_map.t) (_ : Position.t) =
  failwith "TODO: implement Map_state.traction_at"
;;

let feature t id = Map.find t.features id
let features t = Map.data t.features

let features_near
  (_ : t)
  ~map:(_ : Game_map.t)
  ~center:(_ : Position.t)
  ~radius:(_ : float)
  =
  failwith "TODO: implement Map_state.features_near"
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

let viewport
  (_ : t)
  ~map:(_ : Game_map.t)
  ~center:(_ : Position.t)
  ~half_extent_cells:(_ : int)
  =
  failwith "TODO: implement Map_state.viewport"
;;
