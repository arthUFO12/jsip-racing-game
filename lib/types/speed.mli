open! Core

(** How fast a car is moving, in game units per second. Non-negative by
    construction — "going backwards" is a flipped {!Heading.t}, not a
    negative speed, so the sign ambiguity never exists. *)

type t [@@deriving compare, equal, sexp_of]

val zero : t

(** Errors on negative, NaN and infinite values. *)
val of_float : float -> t Or_error.t

(** Like {!of_float}, but raises. *)
val of_float_exn : float -> t

val to_float : t -> float
