open! Core
open! Async
open Racing_types
open Racing_map
open Racing_gateway

(* The interactive racing client. Two roles share one connection and event
   loop but see different screens: a [Driver] gets the close-up driving view
   and steers with WASD; a [Track_player] gets the whole-map console and
   sabotages by clicking the track. Snapshots stream in and drive what we draw;
   the client keeps no game state of its own — every frame is rebuilt from the
   newest snapshot (see rpc_protocol.mli). *)

module Connection = Jsip_client.Connection
module Controls = Jsip_client.Controls
module Client_frame = Jsip_client.Client_frame
module Track_console = Jsip_client.Track_console
module Input = Jsip_client.Input
module Render = Jsip_client_render.Render
module Track_view = Jsip_client_track_view.Track_view

(* Redraw at 60 Hz regardless of the server's 30 tick/s snapshots, so input
   stays responsive and held steer keys are polled often (see input.mli). *)
let frame_span = Time_ns.Span.of_sec (1. /. 60.)

(* Number keys 1..6 select inventory slots 1..6 — one per {!Powerup.t}. *)
let powerup_digits = List.range 1 7

let role_arg =
  Command.Arg_type.create (fun s ->
    match String.lowercase s with
    | "driver" -> Role.Driver
    | "track" | "track-player" | "track_player" -> Role.Track_player
    | other ->
      raise_s
        [%message "role must be 'driver' or 'track-player'" (other : string)])
;;

(* Poll [latest] until [build] can make a frame, yielding between tries. Lets
   us size and open the [Graphics] window before the first {!Input.poll}. *)
let rec wait_for_frame ~latest ~build =
  match Option.bind !latest ~f:build with
  | Some frame -> return frame
  | None ->
    let%bind () = Clock_ns.after frame_span in
    wait_for_frame ~latest ~build
;;

(* A driver spends the powerup in a slot; a track player grants it to their own
   driver — both are targeting-free, so the number row serves either role. *)
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

(* One 60 Hz loop that exits cleanly when the window is closed. [tick] runs
   after each successful {!Input.poll}. *)
let run_loop input ~tick =
  Clock_ns.every frame_span (fun () ->
    try
      Input.poll input;
      tick ()
    with
    | Graphics.Graphic_failure _ -> shutdown 0);
  Deferred.never ()
;;

(* ---- driver: close-up view, WASD ---- *)

let run_driver session input ~map ~self_id ~latest ~window_w ~window_h =
  let build snapshot =
    Client_frame.of_snapshot
      ~map
      ~snapshot
      ~camera_player_id:self_id
      ~self_id
      ~window_w
      ~window_h
  in
  let%bind first = wait_for_frame ~latest ~build in
  Render.open_window first;
  let last_sent = ref Driver_input.idle in
  run_loop input ~tick:(fun () ->
    let intent = Controls.driver_input input in
    if not (Driver_input.equal intent !last_sent)
    then (
      Connection.send_driver_input session intent;
      last_sent := intent);
    match Option.bind !latest ~f:build with
    | None -> ()
    | Some frame -> Render.draw_frame frame)
;;

(* ---- track player: whole-map console, click to sabotage ---- *)

let run_track_player
  session
  input
  ~map
  ~self_id
  ~team
  ~latest
  ~window_w
  ~window_h
  =
  let selected = ref None in
  let build snapshot =
    Track_console.frame_of_snapshot
      ~map
      ~snapshot
      ~my_id:self_id
      ~my_team:team
      ~selected:!selected
      ~window_w
      ~window_h
  in
  let%bind first = wait_for_frame ~latest ~build:(fun s -> Some (build s)) in
  Track_view.open_window first;
  (* A click picks a cell: sabotage the feature there, or drop ice on open
     road. The server has the last word on whether it is legal. *)
  Input.on_click input ~f:(fun ~x ~y ->
    match !latest with
    | None -> ()
    | Some (snapshot : Rpc_protocol.Game_snapshot.t) ->
      (match Track_view.cell_at_px (build snapshot) ~x ~y with
       | None -> ()
       | Some cell ->
         selected := Some cell;
         (match
            Track_console.sabotage_of_cell ~track:snapshot.track ~map ~cell
          with
          | None -> ()
          | Some sabotage ->
            don't_wait_for
              (match%map Connection.use_sabotage session sabotage with
               | Ok () -> ()
               | Error error ->
                 eprintf !"sabotage rejected: %{Error#hum}\n%!" error))));
  run_loop input ~tick:(fun () ->
    match !latest with
    | None -> ()
    | Some snapshot -> Track_view.draw_frame (build snapshot))
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
      !"joined %s as %{sexp:Role.t} (player %{sexp:Player_id.t})\n%!"
      (Game_map.name map)
      role
      self_id;
    (* The pipe reader keeps [latest] fresh; the loops read the newest and drop
       stale (the server already skips old snapshots for slow readers). *)
    don't_wait_for
      (Pipe.iter_without_pushback (Connection.snapshots session) ~f:(fun s ->
         latest := Some s));
    let input = Input.create () in
    List.iter powerup_digits ~f:(fun digit ->
      Input.on_keypress input (Input.Key.Digit digit) ~f:(fun () ->
        handle_digit session ~role ~self_id ~latest digit));
    (match (role : Role.t) with
     | Driver ->
       run_driver session input ~map ~self_id ~latest ~window_w ~window_h
     | Track_player ->
       run_track_player
         session
         input
         ~map
         ~self_id
         ~team
         ~latest
         ~window_w
         ~window_h)
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
