open! Core

type t =
  | Countdown
  | Racing
  | Finished
[@@deriving bin_io, compare, enumerate, equal, sexp_of]
