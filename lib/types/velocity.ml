open! Core

type t =
  { heading : Heading.t
  ; speed : Speed.t
  }
[@@deriving bin_io, compare, equal, sexp_of]

let stationary ~facing = { heading = facing; speed = Speed.zero }
