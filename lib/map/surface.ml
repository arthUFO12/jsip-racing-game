open! Core

type t =
  | Road
  | Wall
  | Trees
[@@deriving sexp, bin_io, compare, equal, enumerate]

let is_solid = function
  | Road -> false
  | Wall | Trees -> true
;;
