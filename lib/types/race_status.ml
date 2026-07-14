open! Core

type t =
  | Countdown
  | Racing
  | Finished
[@@deriving compare, enumerate, equal, sexp_of]
