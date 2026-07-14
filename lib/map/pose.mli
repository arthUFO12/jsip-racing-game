(** A position plus a facing: start-grid slots and checkpoint respawn
    points. [heading] is radians, [0.] pointing along +x, counterclockwise
    positive (consistent with the y-up frame of {!Vec2}). *)

open! Core

type t =
  { pos : Vec2.t
  ; heading : float
  }
[@@deriving sexp, bin_io, compare, equal]
