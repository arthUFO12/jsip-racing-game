(** Translation from live {!Input} to game intents — no [Async], no protocol.
    [main] uses these each frame to turn keyboard input into the
    {!Driver_input.t} and item choices it sends over the {!Connection}. *)

open! Core
open Racing_types

(** The driver's movement keys as of now — standard hold-to-move WASD: [W]/[S]
    accelerate/brake, [A]/[D] steer left/right. Reads held-state via
    {!Input.is_pressed}, so it is only meaningful once {!Input.poll} runs every
    frame. Every combination is legal (opposing keys cancel server-side), and
    accelerating while steering works (see {!Input.is_pressed}). *)
val driver_input : Input.t -> Driver_input.t

(** How the number row maps to a player's held items: digit [n] selects
    inventory slot [n - 1], so [1] is the first item. [None] when the digit is
    out of range or that slot is empty — the caller then sends nothing. *)
val powerup_for_digit
  :  inventory:Powerup.t list
  -> digit:int
  -> Powerup.t option
