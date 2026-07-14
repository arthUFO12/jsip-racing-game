open! Core

type t =
  | Driver
  | Track_player
[@@deriving compare, enumerate, equal, sexp_of]
