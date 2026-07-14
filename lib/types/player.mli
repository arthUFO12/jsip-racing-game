open! Core

(** One participant: who they are and what to call them.

    Note what's missing. There is no role field: a player's role is which
    slot they occupy in their {!Team.t}, so it has a single source of truth
    and "a team with two drivers" is not even writable. Race progress (laps,
    position) isn't here either — that will live in per-driver car state
    (only drivers have any), which arrives together with the track model. *)

type t =
  { id : Player_id.t (** server-assigned; see {!Player_id} *)
  ; name : Player_name.t (** display only; not necessarily unique *)
  }
[@@deriving compare, equal, sexp_of]
