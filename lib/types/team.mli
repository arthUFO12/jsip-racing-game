open! Core

(** A team of exactly two: one driver and one track player. The record shape
    {e is} the invariant — there is no way to write down a team with zero or
    two drivers, which is why {!Player.t} carries no role field.

    The record is [private]: read fields and pattern-match freely, but the
    only way to build one is {!create}, which checks the one thing the shape
    can't — that the two slots hold two different players. *)

type t = private
  { id : Team_id.t
  ; driver : Player.t
  ; track_player : Player.t
  }
[@@deriving compare, equal, sexp_of]

(** Errors if [driver] and [track_player] share a {!Player_id.t}. *)
val create
  :  id:Team_id.t
  -> driver:Player.t
  -> track_player:Player.t
  -> t Or_error.t

(** [None] if the player is not on this team. *)
val role : t -> Player_id.t -> Role.t option
