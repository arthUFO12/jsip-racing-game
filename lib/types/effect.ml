open! Core

module Kind = struct
  type t =
    | Powerup of Powerup.t
    | Vines
    | Mud_bomb
  [@@deriving bin_io, compare, equal, sexp_of]
end

type t =
  { kind : Kind.t
  ; remaining : Time_ns.Span.t
  }
[@@deriving bin_io, compare, equal, sexp_of]
