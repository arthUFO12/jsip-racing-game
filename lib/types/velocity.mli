open! Core

(** How a car is actually moving: which way it points and how fast.

    Polar (heading plus speed) rather than a (vx, vy) vector because a car
    always faces somewhere — even parked — and because {!Speed.t} being
    non-negative removes the "negative speed or flipped heading?" ambiguity a
    vector would reintroduce.

    This is truth about the car, computed by the server; what the driver
    {e wants} is a {!Driver_input.t}. *)

type t =
  { heading : Heading.t
  ; speed : Speed.t
  }
[@@deriving compare, equal, sexp_of]

(** Parked, facing [facing]. *)
val stationary : facing:Heading.t -> t
