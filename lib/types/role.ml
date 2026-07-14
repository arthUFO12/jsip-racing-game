open! Core

type t =
  | Driver
  | Track_player
[@@deriving bin_io, compare, enumerate, equal, sexp_of]
