open! Core

module T = struct
  type t =
    | Speed_boost
    | Invincibility
    | Glider
    | Flame_magic
    | Flashlight
    | Axe
  [@@deriving bin_io, compare, enumerate, equal, hash, sexp]
end

include T
include Comparable.Make (T)
