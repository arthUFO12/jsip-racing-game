open! Core
open Racing_types

(* [Sabotage] rather than [Interference] so the car-targeting
   [Racing_types.Interference] constructors below stay reachable through
   [open Racing_types] instead of being shadowed. *)
module Sabotage = Racing_gateway.Rpc_protocol.Interference
module Track_action = Racing_map.Track_action

let%expect_test "use_interference carries both halves of sabotage, each \
                 still the source library's own type"
  =
  let show t = print_s [%sexp (t : Sabotage.t)] in
  (* the driver-targeting half is a Racing_types.Interference.t, unwrapped *)
  show (Sabotage.On_driver (Interference.Mud_bomb (Player_id.of_int 3)));
  [%expect {| (On_driver (Mud_bomb 3)) |}];
  (* the track-targeting half is a Racing_map.Track_action.t, unwrapped; ice
     lives here as Place_ice, not as a duplicated Slick_track *)
  show
    (Sabotage.On_track (Track_action.Place_ice { Position.x = 4.5; y = 2.5 }));
  [%expect {| (On_track (Place_ice ((x 4.5) (y 2.5)))) |}];
  show
    (Sabotage.On_track
       (Track_action.Collapse_bridge (Racing_map.Feature_id.of_int 1)));
  [%expect {| (On_track (Collapse_bridge 1)) |}]
;;
