open! Core

type t =
  { x : float
  ; y : float
  }
[@@deriving bin_io, compare, equal, sexp_of]

let origin = { x = 0.; y = 0. }
