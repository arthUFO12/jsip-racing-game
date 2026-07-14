open! Core

type t =
  | Vines of Player_id.t
  | Mud_bomb of Player_id.t
[@@deriving bin_io, compare, equal, sexp_of]
