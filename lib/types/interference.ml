open! Core

type t =
  | Slick_track
  | Vines of Player_id.t
  | Mud_bomb of Player_id.t
[@@deriving compare, equal, sexp_of]
