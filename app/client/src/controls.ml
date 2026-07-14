open! Core
open Racing_types

module Driver = struct
  (* The throttle latch is the whole point (see controls.mli): W presses turn
     [accelerate] on, S presses turn it off. Steering is read live each frame
     — one held steer key at a time is what X11 auto-repeat can actually
     track. *)
  type t =
    { input : Input.t
    ; accelerate : bool ref
    }

  let create input =
    let accelerate = ref false in
    Input.on_keypress input Input.Key.W ~f:(fun () -> accelerate := true);
    Input.on_keypress input Input.Key.S ~f:(fun () -> accelerate := false);
    { input; accelerate }
  ;;

  let input t =
    { Driver_input.accelerate = !(t.accelerate)
    ; brake = Input.is_pressed t.input Input.Key.S
    ; steer_left = Input.is_pressed t.input Input.Key.A
    ; steer_right = Input.is_pressed t.input Input.Key.D
    }
  ;;
end

(* Digit [n] selects inventory slot [n - 1] (slots are shown to the player
   1-indexed). [digit < 1] — including the reserved [0] — selects nothing, and
   an out-of-range digit yields [None] via {!List.nth}. *)
let powerup_for_digit ~inventory ~digit =
  if digit < 1 then None else List.nth inventory (digit - 1)
;;
