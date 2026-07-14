open! Core

type t =
  { id : Player_id.t
  ; name : Player_name.t
  }
[@@deriving bin_io, compare, equal, sexp_of]
