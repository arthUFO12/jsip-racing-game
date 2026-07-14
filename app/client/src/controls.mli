(** Pure translation from live input to game intents — no [Graphics], no
    [Async], so every mapping here is expect-testable on its own. [main] calls
    these each frame to turn {!Input} into the {!Driver_input.t} and powerup
    choices it sends over the {!Connection}. *)

open! Core
open Racing_types

(** The driver's four movement keys, read as of now: [W]/[S] accelerate/brake,
    [A]/[D] steer left/right. Every combination is legal — opposing keys
    cancel server-side — so this never fails. Reads held-state via
    {!Input.is_pressed}, so it is only meaningful once {!Input.poll} runs every
    frame. *)
val driver_input : Input.t -> Driver_input.t

(** How the number row maps to a driver's held items: digit [n] selects
    inventory slot [n - 1], so [1] is the first item shown. [None] when the
    digit is out of range or that slot is empty — the caller then sends
    nothing rather than guessing. *)
val powerup_for_digit
  :  inventory:Powerup.t list
  -> digit:int
  -> Powerup.t option
