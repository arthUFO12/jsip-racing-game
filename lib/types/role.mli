open! Core

(** The two halves of a team. A player's role is not a stored field — it is
    which slot of their {!Team.t} they occupy — so this type is for code that
    talks {e about} roles: join requests, permission checks, UI labels.

    (The brainstorm mentions switching roles mid-game; with roles as team
    slots, that is just building a new {!Team.t} with the slots swapped.) *)

type t =
  | Driver (** steers the car, and sees only the track near it *)
  | Track_player
  (** sees the whole track: warns their driver, grants powerups, and
      sabotages other teams with {!Interference.t} *)
[@@deriving bin_io, compare, enumerate, equal, sexp_of]
