(** Adapter between the game protocol and the track player's console
    ({!Jsip_client_track_view.Track_view}). It lives in the client — which
    knows both the gateway snapshots and the render libraries — so the console
    library stays protocol-free. Mirrors {!Client_frame} (the driver's-eye
    adapter) for the co-pilot's whole-map view. *)

open! Core
open Racing_types
open Racing_map
open Racing_gateway

(** Build the co-pilot's console frame from the latest snapshot: the whole map,
    every car as a dot (the co-pilot's own driver ringed), the co-pilot's own
    item stock, and the current [selected] sabotage-target cursor. [my_id] is
    the co-pilot; [my_team] identifies which car is their driver's. *)
val frame_of_snapshot
  :  map:Game_map.t
  -> snapshot:Rpc_protocol.Game_snapshot.t
  -> my_id:Player_id.t
  -> my_team:Team_id.t
  -> selected:Cell.t option
  -> window_w:int
  -> window_h:int
  -> Jsip_client_track_view.Track_view.Frame.t

(** The sabotage a click on [cell] should trigger: the {!Track_action} matching
    a feature sitting on that cell (collapse a bridge, close a gate, drop a
    stalactite), or fresh ice when the cell is open road. [None] when the cell
    holds nothing sabotageable (an existing ice patch, a wall, trees) — the
    caller then does nothing. The server still has the final say (rest phase,
    footprint on road). *)
val sabotage_of_cell
  :  track:Map_state.t
  -> map:Game_map.t
  -> cell:Cell.t
  -> Rpc_protocol.Sabotage.t option
