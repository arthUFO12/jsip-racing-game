open! Core
open Racing_types

let driver_input input =
  { Driver_input.accelerate = Input.is_pressed input Input.Key.W
  ; brake = Input.is_pressed input Input.Key.S
  ; steer_left = Input.is_pressed input Input.Key.A
  ; steer_right = Input.is_pressed input Input.Key.D
  }
;;

(* Digit [n] selects inventory slot [n - 1] (slots are shown to the player
   1-indexed). [digit < 1] — including the reserved [0] — selects nothing,
   and an out-of-range digit yields [None] via {!List.nth}. *)
let powerup_for_digit ~inventory ~digit =
  if digit < 1 then None else List.nth inventory (digit - 1)
;;
