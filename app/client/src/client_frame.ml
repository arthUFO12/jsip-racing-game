(** The one client-logic file coupled to the render library's {!Render.Frame.t}.

    Everything else in the client speaks snapshots ({!Rpc_protocol}) and domain
    vocabulary ({!Racing_types}); the renderer speaks its own {!Render.Frame.t}
    of a viewport plus flat car and HUD facts. This module is the single seam
    between the two, so when the renderer's frame shape changes this is the only
    place to reconcile.

    Two knobs here are provisional and expected to move as gameplay firms up:
    [half_extent_cells] (how much track the driver sees) and the [place]
    ordering (a plain progress sort, no tie-breaking on distance-to-checkpoint
    or finish order). Both carry comments where they are used. *)

open! Core
open Racing_types
open Racing_map
open Racing_gateway
module Render = Jsip_client_render.Render

(* Half-width of the square terrain slice we hand the renderer: a
   [2 * n + 1] = 17x17 block of cells around the camera car. Provisional — a
   comfortable close-up for now, not a tuned field of view. *)
let half_extent_cells = 8

let of_snapshot
  ~map
  ~(snapshot : Rpc_protocol.Game_snapshot.t)
  ~camera_player_id
  ~self_id
  ~window_w
  ~window_h
  =
  match Map.find snapshot.cars camera_player_id with
  | None ->
    (* No car to center on (e.g. a track player before their driver spawns);
       the caller draws nothing this frame. *)
    None
  | Some cam_car ->
    (* [Player_id -> Team_id], built once, for coloring every visible car by
       its driver's team. *)
    let team_by_player =
      List.fold
        snapshot.players
        ~init:Player_id.Map.empty
        ~f:(fun acc (info : Rpc_protocol.Player_info.t) ->
          Map.set acc ~key:info.player.id ~data:info.team)
    in
    let team_of pid =
      (* A driver with a car is always in [players]; the default only guards
         an impossible snapshot rather than crashing the render loop. *)
      Option.value (Map.find team_by_player pid) ~default:(Team_id.of_int 0)
    in
    let cars =
      Map.to_alist snapshot.cars
      |> List.map ~f:(fun (pid, (car : Rpc_protocol.Car.t)) ->
        { Render.Car.pos = car.position
        ; heading = car.velocity.heading
        ; team = team_of pid
        ; is_self = Player_id.equal pid self_id
        ; effects = Map.find_multi snapshot.effects pid
        })
    in
    let viewport =
      Map_state.viewport
        snapshot.track
        ~map
        ~center:cam_car.position
        ~half_extent_cells
    in
    let cam_progress : Checkpoint.Progress.t = cam_car.progress in
    (* Provisional placing: rank purely by race progress — more laps first,
       then a higher next checkpoint index = further round the lap. Ties share
       a place; no distance-within-segment or finish-order tie-break yet. *)
    let ahead =
      Map.count snapshot.cars ~f:(fun (other : Rpc_protocol.Car.t) ->
        let p = other.progress in
        p.laps_completed > cam_progress.laps_completed
        || (p.laps_completed = cam_progress.laps_completed
            && p.next_index > cam_progress.next_index))
    in
    let place = ahead + 1 in
    (* Ticks are the server's clock; {!Game_state} owns the tick rate, so scale
       its per-tick duration by the elapsed tick count for wall-clock race
       time. *)
    let time_elapsed =
      Time_ns.Span.scale
        Game_state.tick_duration
        (Float.of_int (Tick.to_int snapshot.tick))
    in
    Some
      { Render.Frame.viewport
      ; (* World-units-per-cell, passed straight through to the camera:
           [scene_of_frame] hands [frame.cell_size] to [Camera.create ~cell_size],
           whose doc says it "is the map's world-units-per-cell
           ({!Racing_map.Game_map.cell_size})" — the camera squares cells to
           pixels itself from the window area, and uses this only to place a
           car's continuous {!Position.t} within its cell. *)
        cell_size = Game_map.cell_size map
      ; cars
      ; track_name = Game_map.name map
      ; lap = cam_progress.laps_completed + 1 (* 1-based current lap *)
      ; laps_to_win = Game_map.laps_to_win map
      ; speed = Some cam_car.velocity.speed
      ; place = Some place
      ; time_elapsed = Some time_elapsed
      ; window_w
      ; window_h
      }
;;
