(** Translation from live {!Input} to game intents — no [Async], no protocol.
    [main] uses these to turn keyboard input into the {!Driver_input.t} and
    item choices it sends over the {!Connection}. *)

open! Core
open Racing_types

(** A driver's throttle is {e latched}, not held. OCaml [Graphics] reports only
    key presses (no releases), and X11 auto-repeats just the most-recently
    pressed key — so "hold W to accelerate while holding A to steer" cannot be
    read reliably (pressing A stops W's repeat, and W then reads as released).

    So the throttle is a latch: [W] turns it on, [S] turns it off and brakes.
    Steering ([A]/[D]) is read live via {!Input.is_pressed}, which is reliable
    because you only hold one steer key at a time. Net feel: tap [W] to go,
    hold [A]/[D] to turn, tap [S] to slow — and, crucially, accelerating and
    steering at the same time actually works. *)
module Driver : sig
  type t

  (** Register the [W]/[S] throttle-latch handlers on [input]. Call once, then
      read {!input} every frame (after {!Input.poll} has run). *)
  val create : Input.t -> t

  (** The current {!Driver_input.t}: latched throttle plus live steering. *)
  val input : t -> Driver_input.t
end

(** How the number row maps to a player's held items: digit [n] selects
    inventory slot [n - 1], so [1] is the first item. [None] when the digit is
    out of range or that slot is empty — the caller then sends nothing. *)
val powerup_for_digit
  :  inventory:Powerup.t list
  -> digit:int
  -> Powerup.t option
