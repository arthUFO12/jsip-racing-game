open! Core
open Racing_types
open Racing_map
open Racing_gateway
module Track_view = Jsip_client_track_view.Track_view

let frame_of_snapshot
  ~map
  ~(snapshot : Rpc_protocol.Game_snapshot.t)
  ~my_id
  ~my_team
  ~selected
  ~window_w
  ~window_h
  =
  let info_of pid =
    List.find snapshot.players ~f:(fun (info : Rpc_protocol.Player_info.t) ->
      Player_id.equal info.player.id pid)
  in
  let cars =
    Map.to_alist snapshot.cars
    |> List.map ~f:(fun (pid, (car : Rpc_protocol.Car.t)) ->
      let team, name =
        match info_of pid with
        | Some info -> info.team, Player_name.to_string info.player.name
        | None -> Team_id.of_int 0, "?"
      in
      { Track_view.Car_view.position = car.position
      ; velocity = car.velocity
      ; team
      ; name
      ; laps_completed = car.progress.laps_completed
      ; is_own_driver = Team_id.equal team my_team
      })
  in
  { Track_view.Frame.game_map = map
  ; track = snapshot.track
  ; cars
  ; inventory = Map.find_multi snapshot.inventories my_id
  ; race_status = snapshot.race_status
  ; selected
  ; window_w
  ; window_h
  }
;;

let same_cell (a : Cell.t) (b : Cell.t) = a.col = b.col && a.row = b.row

let sabotage_of_cell ~(track : Map_state.t) ~map ~cell =
  let feature_here =
    List.find (Map_state.features track) ~f:(fun (feature : Feature.t) ->
      List.exists feature.cells ~f:(same_cell cell))
  in
  match feature_here with
  | Some feature ->
    (* A feature has exactly one natural sabotage; an ice patch already placed
       has none. *)
    let action : Track_action.t option =
      match Feature.kind feature with
      | Feature.Kind.Bridge -> Some (Collapse_bridge feature.id)
      | Feature.Kind.Gate -> Some (Close_gate feature.id)
      | Feature.Kind.Stalactite -> Some (Drop_stalactite feature.id)
      | Feature.Kind.Ice_patch -> None
    in
    Option.map action ~f:(fun action -> Rpc_protocol.Sabotage.Track action)
  | None ->
    (* Empty cell: ice, but only on open road (walls and trees can't be iced —
       and the server rejects it anyway). *)
    let center = Cell.center cell ~cell_size:(Game_map.cell_size map) in
    (match (Map_state.surface_at track ~map center : Surface.t) with
     | Road -> Some (Rpc_protocol.Sabotage.Track (Place_ice center))
     | Wall | Trees -> None)
;;
