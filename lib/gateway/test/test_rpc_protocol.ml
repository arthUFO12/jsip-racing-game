open! Core
open Racing_types
open Racing_map
open Racing_gateway

(* Encode to bin_prot bytes and decode back — what actually happens to every
   payload on the wire. If a protocol type loses information here, clients
   and server disagree about the world. *)
let round_trip
  (type a)
  (module M : Binable.S with type t = a)
  (sexp_of_a : a -> Sexp.t)
  value
  =
  Binable.to_string (module M) value
  |> Binable.of_string (module M)
  |> sexp_of_a
  |> print_s
;;

let%expect_test "client-to-server payloads survive the wire" =
  round_trip
    (module Rpc_protocol.Join_request)
    [%sexp_of: Rpc_protocol.Join_request.t]
    { name = "Robyn"; team = Team_id.of_int 3; role = Driver };
  [%expect {| ((name Robyn) (team 3) (role Driver)) |}];
  round_trip
    (module Driver_input)
    [%sexp_of: Driver_input.t]
    { Driver_input.idle with accelerate = true; steer_left = true };
  [%expect
    {|
    ((accelerate true) (brake false) (steer_left true) (steer_right false))
    |}]
;;

let%expect_test "both kinds of sabotage ride one payload" =
  round_trip
    (module Rpc_protocol.Sabotage)
    [%sexp_of: Rpc_protocol.Sabotage.t]
    (Car (Vines (Player_id.of_int 7)));
  [%expect {| (Car (Vines 7)) |}];
  round_trip
    (module Rpc_protocol.Sabotage)
    [%sexp_of: Rpc_protocol.Sabotage.t]
    (Track (Close_gate (Feature_id.of_int 2)));
  [%expect {| (Track (Close_gate 2)) |}];
  round_trip
    (module Rpc_protocol.Sabotage)
    [%sexp_of: Rpc_protocol.Sabotage.t]
    (Track (Place_ice { x = 4.5; y = 1.5 }));
  [%expect {| (Track (Place_ice ((x 4.5) (y 1.5)))) |}]
;;

let%expect_test "the protocol at a glance: wire names and versions" =
  let module Rpc = Async_rpc_kernel.Rpc in
  List.iter
    ~f:(fun description -> print_s [%sexp (description : Rpc.Description.t)])
    [ Rpc.Rpc.description Rpc_protocol.join_game_rpc
    ; Rpc.Pipe_rpc.description Rpc_protocol.game_feed_rpc
    ; Rpc.One_way.description Rpc_protocol.driver_input_rpc
    ; Rpc.Rpc.description Rpc_protocol.use_powerup_rpc
    ; Rpc.Rpc.description Rpc_protocol.use_interference_rpc
    ; Rpc.Rpc.description Rpc_protocol.assist_teammate_rpc
    ];
  [%expect
    {|
    ((name join-game) (version 1))
    ((name game-feed) (version 1))
    ((name driver-input) (version 1))
    ((name use-powerup) (version 1))
    ((name use-interference) (version 1))
    ((name assist-teammate) (version 1))
    |}]
;;
