(** A live client session to the racing server: one TCP/RPC connection with a
    player already seated, plus the per-tick snapshot feed and typed helpers
    for every intent a client can send.

    All of the client's networking lives here — {!Controls} and
    {!Client_frame} are pure, and [main] should never reach for [Async_rpc]
    directly. The session mirrors the server ({!Racing_gateway.Server}): the
    connection {e is} the identity, so no send helper carries a
    {!Player_id.t}; the server attributes every command to whoever joined on
    this connection. *)

open! Core
open! Async
open Racing_types
open Racing_gateway

type t

(** Connect to [host]:[port], subscribe to the snapshot feed, and take a seat
    as [name] on [team] in [role]. The returned [t] owns the connection, the
    server-assigned {!Player_id.t}, the immutable {!Racing_map.Game_map.t}, and
    the live feed. Errors: the connection failed, or the server rejected the
    join (invalid name, or the seat is already taken). *)
val connect_and_join
  :  host:string
  -> port:int
  -> name:string
  -> team:Team_id.t
  -> role:Role.t
  -> t Or_error.t Deferred.t

val player_id : t -> Player_id.t
val map : t -> Racing_map.Game_map.t

(** The per-tick world feed: one complete {!Rpc_protocol.Game_snapshot.t} per
    server tick. Render the newest and drop stale — the server already skips
    old snapshots for slow readers, so this pipe never runs far ahead. *)
val snapshots : t -> Rpc_protocol.Game_snapshot.t Pipe.Reader.t

(** Fire-and-forget the driver's key intent (a one-way RPC — confirmation is
    the next snapshot, never a reply). Cheap to call, but [main] still sends
    only when the key state actually changes. *)
val send_driver_input : t -> Driver_input.t -> unit

(** A driver spends a held powerup; a track player grants one of their stock
    powerups to their own driver. Errors surface the server's [Or_error]
    (wrong role, not held, race not running, ...). *)
val use_powerup : t -> Powerup.t -> unit Or_error.t Deferred.t

val assist_teammate : t -> Powerup.t -> unit Or_error.t Deferred.t

(** A track player invokes sabotage — car-targeted ({!Interference.t}) or
    track-targeted ({!Racing_map.Track_action.t}), unified by
    {!Rpc_protocol.Sabotage.t}. Errors mirror {!use_interference_rpc}. *)
val use_sabotage : t -> Rpc_protocol.Sabotage.t -> unit Or_error.t Deferred.t
