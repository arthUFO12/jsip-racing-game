open! Core
open Racing_types

type t =
  { pos : Position.t
  ; heading : float
  }
[@@deriving sexp, bin_io, compare, equal]
