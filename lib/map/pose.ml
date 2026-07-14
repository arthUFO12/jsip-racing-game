open! Core

type t =
  { pos : Vec2.t
  ; heading : float
  }
[@@deriving sexp, bin_io, compare, equal]
