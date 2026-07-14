open! Core
open! Async

(* Boots the authoritative racing-game server: load the track, bind the port,
   run until killed. The map file format is doc/map-design.md. *)

let command =
  Command.async
    ~summary:"Run the authoritative racing-game server"
    [%map_open.Command
      let port =
        flag "-port" (required int) ~doc:"PORT listen for clients here"
      and map_file =
        flag
          "-map"
          (required string)
          ~doc:"FILE track layout sexp (schema in doc/map-design.md)"
      in
      fun () ->
        let map = Racing_map.Game_map.load_file_exn map_file in
        let%bind server = Racing_gateway.Server.create ~map ~port in
        printf
          "racing-game server: map %s, listening on port %d\n"
          (Racing_map.Game_map.name map)
          (Racing_gateway.Server.port server);
        Deferred.never ()]
;;

let () = Command_unix.run command
