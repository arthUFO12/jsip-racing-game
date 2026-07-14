open! Core
open! Async
open Racing_types
open Racing_gateway

(* The interactive racing client: connect to the authoritative server, take a
   seat, then run a render/input loop. Two one-way flows meet here — snapshots
   stream in from the server and drive what we draw; local WASD input streams
   out as [Driver_input.t]. The client holds no game state of its own: every
   frame is built fresh from the newest snapshot (see rpc_protocol.mli). *)

module Connection = Jsip_client.Connection
module Controls = Jsip_client.Controls
module Client_frame = Jsip_client.Client_frame
module Input = Jsip_client.Input
module Render = Jsip_client_render.Render

(* Redraw at 60 Hz regardless of the server's 30 tick/s snapshot rate, so
   input feels responsive and held keys are polled often enough for
   {!Input.is_pressed} to track them (see input.mli on auto-repeat). *)
let frame_span = Time_ns.Span.of_sec (1. /. 60.)

(* Number keys 1..6 select inventory slots 1..6 — one per {!Powerup.t}. *)
let powerup_digits = List.range 1 7

let role_arg =
  Command.Arg_type.create (fun s ->
    match String.lowercase s with
    | "driver" -> Role.Driver
    | "track" | "track-player" | "track_player" -> Role.Track_player
    | other ->
      raise_s [%message "role must be 'driver' or 'track-player'" (other : string)])
;;

(* Which car the camera follows: a driver watches their own car; a track
   player rides along with their team's driver (their whole-map console is a
   separate view, still being built). [None] until that car exists. *)
let camera_player_id ~role ~self_id ~team (snapshot : Rpc_protocol.Game_snapshot.t)
  =
  match (role : Role.t) with
  | Driver -> Some self_id
  | Track_player ->
    List.find_map snapshot.players ~f:(fun (info : Rpc_protocol.Player_info.t) ->
      match info.role with
      | Driver when Team_id.equal info.team team -> Some info.player.id
      | Driver | Track_player -> None)
;;

let frame_of snapshot ~map ~role ~self_id ~team ~window_w ~window_h =
  match camera_player_id ~role ~self_id ~team snapshot with
  | None -> None
  | Some camera_player_id ->
    Client_frame.of_snapshot
      ~map
      ~snapshot
      ~camera_player_id
      ~self_id
      ~window_w
      ~window_h
;;

(* A driver spends the powerup in a slot; a track player grants it to their
   own driver — both are targeting-free, so the number row works for either
   role. (Track-targeted sabotage — collapsing bridges, dropping stalactites —
   needs the whole-map view to aim, so it is not wired here yet.) *)
let handle_digit session ~role ~self_id ~latest digit =
  match !latest with
  | None -> ()
  | Some (snapshot : Rpc_protocol.Game_snapshot.t) ->
    let inventory = Map.find_multi snapshot.inventories self_id in
    (match Controls.powerup_for_digit ~inventory ~digit with
     | None -> ()
     | Some powerup ->
       let send =
         match (role : Role.t) with
         | Driver -> Connection.use_powerup session powerup
         | Track_player -> Connection.assist_teammate session powerup
       in
       don't_wait_for
         (match%map send with
          | Ok () -> ()
          | Error error -> eprintf !"item rejected: %{Error#hum}\n%!" error))
;;

(* Read snapshots until we can build a frame, so we can size and open the
   window before the first {!Input.poll} (which [Graphics] requires). Records
   the newest snapshot into [latest] as it goes. *)
let rec wait_for_first_frame
  session
  ~map
  ~role
  ~self_id
  ~team
  ~window_w
  ~window_h
  ~latest
  =
  match%bind Pipe.read (Connection.snapshots session) with
  | `Eof -> return None
  | `Ok snapshot ->
    latest := Some snapshot;
    (match frame_of snapshot ~map ~role ~self_id ~team ~window_w ~window_h with
     | Some frame -> return (Some frame)
     | None ->
       wait_for_first_frame
         session
         ~map
         ~role
         ~self_id
         ~team
         ~window_w
         ~window_h
         ~latest)
;;

let run ~host ~port ~name ~team ~role ~window_w ~window_h =
  match%bind Connection.connect_and_join ~host ~port ~name ~team ~role with
  | Error error ->
    eprintf !"could not join: %{Error#hum}\n%!" error;
    return ()
  | Ok session ->
    let map = Connection.map session in
    let self_id = Connection.player_id session in
    let latest : Rpc_protocol.Game_snapshot.t option ref = ref None in
    printf
      !"joined %s as %{sexp:Role.t} (player %{sexp:Player_id.t}); waiting for \
        the first snapshot...\n\
        %!"
      (Racing_map.Game_map.name map)
      role
      self_id;
    (match%bind
       wait_for_first_frame
         session
         ~map
         ~role
         ~self_id
         ~team
         ~window_w
         ~window_h
         ~latest
     with
     | None ->
       eprintf "server closed the feed before any frame was ready\n%!";
       return ()
     | Some first_frame ->
       Render.open_window first_frame;
       (* From here the pipe reader just keeps [latest] fresh; the render loop
          reads it. A dropped snapshot costs nothing — the next supersedes it. *)
       don't_wait_for
         (Pipe.iter_without_pushback (Connection.snapshots session) ~f:(fun s ->
            latest := Some s));
       let input = Input.create () in
       List.iter powerup_digits ~f:(fun digit ->
         Input.on_keypress input (Input.Key.Digit digit) ~f:(fun () ->
           handle_digit session ~role ~self_id ~latest digit));
       let last_sent = ref Driver_input.idle in
       Clock_ns.every frame_span (fun () ->
         match Input.poll input with
         | exception Graphics.Graphic_failure _ ->
           (* The window was closed — leave the game. *)
           shutdown 0
         | () ->
           (match (role : Role.t) with
            | Track_player -> ()
            | Driver ->
              let intent = Controls.driver_input input in
              if not (Driver_input.equal intent !last_sent)
              then (
                Connection.send_driver_input session intent;
                last_sent := intent));
           (match !latest with
            | None -> ()
            | Some snapshot ->
              (match
                 frame_of snapshot ~map ~role ~self_id ~team ~window_w ~window_h
               with
               | None -> ()
               | Some frame -> Render.draw_frame frame)));
       Deferred.never ())
;;

let command =
  Command.async
    ~summary:"Play the racing game: connect to a server and drive"
    [%map_open.Command
      let port = flag "-port" (required int) ~doc:"PORT server port"
      and host =
        flag
          "-host"
          (optional_with_default "localhost" string)
          ~doc:"HOST server host (default localhost)"
      and name = flag "-name" (required string) ~doc:"NAME your display name"
      and team =
        flag
          "-team"
          (required int)
          ~doc:"N team number to join (teammates share one)"
      and role =
        flag "-role" (required role_arg) ~doc:"ROLE 'driver' or 'track-player'"
      and window_w =
        flag
          "-width"
          (optional_with_default 960 int)
          ~doc:"PX window width (default 960)"
      and window_h =
        flag
          "-height"
          (optional_with_default 720 int)
          ~doc:"PX window height (default 720)"
      in
      fun () ->
        run
          ~host
          ~port
          ~name
          ~team:(Team_id.of_int team)
          ~role
          ~window_w
          ~window_h]
;;

let () = Command_unix.run command
