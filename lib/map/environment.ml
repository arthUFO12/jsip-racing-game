open! Core

type t =
  | Forest
  | Castle
  | Cave
[@@deriving sexp, bin_io, compare, equal, enumerate]

let is_dark = function Cave -> true | Forest | Castle -> false
