open! Core

module T = struct
  type t =
    | Speed_boost
    | Invincibility
    | Glider
    | Flame_magic
    | Flashlight
    | Axe
  [@@deriving compare, enumerate, equal, hash, sexp]
end

include T
include Comparable.Make (T)
