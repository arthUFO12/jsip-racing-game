(* The client's entire networking surface: one Async-RPC connection to the
   racing server with a player already seated. Mirrors
   {!Racing_gateway.Server} — the connection {e is} the identity, so nothing
   we send carries a [Player_id.t]; the server attributes every command to
   whoever joined on this connection. Everything above this ({!Controls},
   {!Client_frame}, [main]) stays pure and never touches [Async_rpc]. *)

open! Core
open! Async
open Racing_types
open Racing_gateway

type t =
  { conn : Rpc.Connection.t
  ; player_id : Player_id.t
  ; map : Racing_map.Game_map.t
  ; snapshots : Rpc_protocol.Game_snapshot.t Pipe.Reader.t
  }

let connect_and_join ~host ~port ~name ~team ~role =
  let open Deferred.Or_error.Let_syntax in
  (* [Rpc.Connection.client] fails with a bare [exn]; lift it into [Error.t]
     so the whole join threads through one [Or_error] monad. *)
  let%bind conn =
    Rpc.Connection.client
      (Tcp.Where_to_connect.of_host_and_port { host; port })
    |> Deferred.map ~f:(Result.map_error ~f:Error.of_exn)
  in
  (* Two failure layers collapse with [Or_error.join]: the outer is the
     dispatch itself (could the message even round-trip?), the inner is the
     server's verdict ([join_game_rpc] returns [Joined.t Or_error.t] — bad
     name, seat taken, already joined). *)
  let request = { Rpc_protocol.Join_request.name; team; role } in
  let%bind (joined : Rpc_protocol.Joined.t) =
    Rpc.Rpc.dispatch Rpc_protocol.join_game_rpc conn request
    |> Deferred.map ~f:Or_error.join
  in
  (* Same two-layer flatten for the feed: dispatch error vs. the pipe's own
     [Error.t]. We keep only the reader; the subscription metadata is unused. *)
  let%bind reader, _metadata =
    Rpc.Pipe_rpc.dispatch Rpc_protocol.game_feed_rpc conn ()
    |> Deferred.map ~f:Or_error.join
  in
  return
    { conn
    ; player_id = joined.player_id
    ; map = joined.map
    ; snapshots = reader
    }
;;

let player_id t = t.player_id
let map t = t.map
let snapshots t = t.snapshots

let send_driver_input t input =
  (* One-way and fire-and-forget: confirmation is the next snapshot, so the
     synchronous [Or_error] result (only a local encoding failure) is dropped. *)
  ignore
    (Rpc.One_way.dispatch Rpc_protocol.driver_input_rpc t.conn input
     : unit Or_error.t)
;;

let use_powerup t powerup =
  Rpc.Rpc.dispatch Rpc_protocol.use_powerup_rpc t.conn powerup
  |> Deferred.map ~f:Or_error.join
;;

let assist_teammate t powerup =
  Rpc.Rpc.dispatch Rpc_protocol.assist_teammate_rpc t.conn powerup
  |> Deferred.map ~f:Or_error.join
;;

let use_sabotage t sabotage =
  Rpc.Rpc.dispatch Rpc_protocol.use_interference_rpc t.conn sabotage
  |> Deferred.map ~f:Or_error.join
;;
