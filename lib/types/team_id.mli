open! Core

(** A globally unique identifier for one team of two (a driver plus a track
    player — see {!Team.t}). Abstract for the same reason as {!Player_id.t}:
    so team ids, player ids and plain [int]s can never be mixed up. *)

type t [@@deriving hash, sexp]

include Comparable.S with type t := t
include Hashable.S with type t := t

(** For the server-side allocator and tests, like {!Player_id.of_int}. *)
val of_int : int -> t

val to_int : t -> int
