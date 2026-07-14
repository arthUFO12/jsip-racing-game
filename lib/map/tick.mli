(** A tick of the server game loop — the game's logical clock.

    The loop advances one tick per frame at a fixed rate it owns (e.g.
    30/s). Every feature timer in {!Map_state} is an absolute expiry tick
    ([reopens_at], not "in 3 seconds"), which keeps transitions
    deterministic: expect tests jump time forward instead of sleeping, and
    replaying the same actions at the same ticks rebuilds the same state.
    The server stamps its current tick into every broadcast; clients
    animate telegraph countdowns from [expiry - now] without trusting
    their own clocks. *)

open! Core

type t [@@deriving sexp, bin_io, compare, equal, hash]

include Comparable.S with type t := t

(** The tick before the race starts. *)
val zero : t

val next : t -> t

(** [add t n] is [t] advanced by [n] ticks. Gameplay durations (how long a
    gate stays closed) are tick counts, converted from seconds by whoever
    owns the tick rate. *)
val add : t -> int -> t
