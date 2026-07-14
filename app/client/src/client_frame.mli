(** The client-logic ↔ render seam: fold one
    {!Rpc_protocol.Game_snapshot.t} (plus the immutable map) into the pure
    {!Jsip_client_render.Render.Frame.t} the renderer draws.

    Kept deliberately small and in one place. The render library owns the
    [Frame.t] shape and all the art; this is the only client-logic file that
    depends on it, so when the renderer grows, this is the single point to
    reconcile. *)

open! Core
open Racing_types
open Racing_gateway

(** Build the driver's-eye frame centered on [camera_player_id]'s car, sized
    to [window_w] x [window_h]. [self_id]'s car gets the "you" marker.

    Returns [None] when [camera_player_id] has no car in this snapshot (a
    track player whose driver has not joined, or before cars spawn) — the
    caller simply draws nothing that frame. Lap, place and elapsed-time HUD
    copy are read straight from the snapshot. *)
val of_snapshot
  :  map:Racing_map.Game_map.t
  -> snapshot:Rpc_protocol.Game_snapshot.t
  -> camera_player_id:Player_id.t
  -> self_id:Player_id.t
  -> window_w:int
  -> window_h:int
  -> Jsip_client_render.Render.Frame.t option
