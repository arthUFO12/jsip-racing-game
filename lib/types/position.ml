open! Core

type t =
  { x : float
  ; y : float
  }
[@@deriving compare, equal, sexp_of]

let origin = { x = 0.; y = 0. }
