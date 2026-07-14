(** A position plus a facing: start-grid slots and checkpoint respawn points.
    [heading] is radians, [0.] pointing along +x, counterclockwise positive
    (consistent with the y-up frame of {!Racing_types.Position}). *)

open! Core
open Racing_types

type t =
  { pos : Position.t
  ; heading : float
  }
[@@deriving sexp, bin_io, compare, equal]
