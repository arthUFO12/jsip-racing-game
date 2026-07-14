open! Core

(** A location on the track, in game units. Purely a coordinate — what is
    {e at} it (road, bridge, water) is the track model's business, which
    deliberately doesn't live in this library yet.

    These floats are server physics output (machine data), so unlike
    {!Player_name} there is no human-input validation here. *)

type t =
  { x : float
  ; y : float
  }
[@@deriving bin_io, compare, equal, sexp_of]

val origin : t
