open! Core
open! Async
open Racing_types

module Connection_state = struct
  (* What the gateway knows about one TCP client: which player, if any,
     joined on this connection. This is the whole session story — identity
     lives here, never in payloads (rpc_protocol.mli). *)
  type t = { mutable player : Player_id.t option }
end

type t =
  { game : Game_state.t
  ; subscribers : Rpc_protocol.Game_snapshot.t Pipe.Writer.t Bag.t
  ; tcp_server : (Socket.Address.Inet.t, int) Tcp.Server.t
  }

(* Per subscriber: how many unread snapshots may sit in the pipe before we
   start skipping. Two, not more — a client that is behind wants the newest
   world, not a tour of the ones it missed. *)
let max_buffered_snapshots = 2

let broadcast t =
  let snapshot = Game_state.snapshot t.game in
  Bag.iter t.subscribers ~f:(fun pipe ->
    if (not (Pipe.is_closed pipe))
       && Pipe.length pipe < max_buffered_snapshots
    then Pipe.write_without_pushback pipe snapshot)
;;

let handle_join game (state : Connection_state.t) request =
  match state.player with
  | Some player_id ->
    Or_error.error_s
      [%message
        "this connection already joined as a player"
          (player_id : Player_id.t)]
  | None ->
    let open Or_error.Let_syntax in
    let%map player_id = Game_state.join game request in
    state.player <- Some player_id;
    { Rpc_protocol.Joined.player_id; map = Game_state.game_map game }
;;

let require_joined (state : Connection_state.t) ~f =
  match state.player with
  | None -> Or_error.error_string "join the game first"
  | Some player_id -> f player_id
;;

let implementations game subscribers =
  Rpc.Implementations.create_exn
    ~implementations:
      [ Rpc.Rpc.implement' Rpc_protocol.join_game_rpc (handle_join game)
      ; Rpc.Pipe_rpc.implement
          Rpc_protocol.game_feed_rpc
          (fun (_ : Connection_state.t) () ->
             (* Anyone may watch, joined or not — the driver, the track
                player, and any monitor all render from this same feed. *)
             let reader, writer = Pipe.create () in
             let subscriber = Bag.add subscribers writer in
             don't_wait_for
               (let%map () = Pipe.closed writer in
                Bag.remove subscribers subscriber);
             return (Ok reader))
      ; Rpc.One_way.implement
          Rpc_protocol.driver_input_rpc
          (fun (state : Connection_state.t) input ->
             match state.player with
             | None -> () (* one-way: nothing to drive, no way to complain *)
             | Some player_id ->
               Game_state.set_driver_input game player_id input)
      ; Rpc.Rpc.implement' Rpc_protocol.use_powerup_rpc (fun state powerup ->
          require_joined state ~f:(fun player_id ->
            Game_state.use_powerup game player_id powerup))
      ; Rpc.Rpc.implement'
          Rpc_protocol.use_interference_rpc
          (fun state sabotage ->
             require_joined state ~f:(fun player_id ->
               Game_state.use_interference game player_id sabotage))
      ; Rpc.Rpc.implement'
          Rpc_protocol.assist_teammate_rpc
          (fun state powerup ->
             require_joined state ~f:(fun player_id ->
               Game_state.assist_teammate game player_id powerup))
      ]
    ~on_unknown_rpc:`Close_connection
    ~on_exception:Log_on_background_exn
;;

let create ~map ~port =
  let game = Game_state.create ~map in
  let subscribers = Bag.create () in
  let%map tcp_server =
    Rpc.Connection.serve
      ~implementations:(implementations game subscribers)
      ~initial_connection_state:
        (fun
          (_ : Socket.Address.Inet.t)
          (_ : Rpc.Connection.t)
          : Connection_state.t
        -> { player = None })
      ~where_to_listen:(Tcp.Where_to_listen.of_port port)
      ()
  in
  let t = { game; subscribers; tcp_server } in
  Clock_ns.every Game_state.tick_duration (fun () ->
    Game_state.step t.game;
    broadcast t);
  t
;;

let port t = Tcp.Server.listening_on t.tcp_server
