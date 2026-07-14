open! Core

(** A monotonic counter stamped on every snapshot the server pushes. Clients
    keep only the newest snapshot; a stale one (smaller tick) is dropped, not
    rendered — "latest wins" in [doc/rpc-protocol.md].

    {[
      Tick.( < ) Tick.zero (Tick.next Tick.zero) (* true *)
    ]} *)

type t [@@deriving hash, sexp]

include Comparable.S with type t := t

(** The tick before the first snapshot. *)
val zero : t

val next : t -> t

(** For tests and debugging output. *)
val of_int : int -> t

val to_int : t -> int
