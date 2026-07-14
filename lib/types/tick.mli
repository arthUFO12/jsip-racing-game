open! Core

(** A tick of the server game loop — the game's logical clock, and the
    monotonic stamp on every snapshot the server pushes.

    Two jobs, one counter:

    - Freshness: clients keep only the newest snapshot; a stale one (smaller
      tick) is dropped, not rendered — "latest wins" in
      [doc/rpc-protocol.md].
    - Timers: gameplay deadlines (when a collapsed bridge rebuilds, when ice
      melts) are absolute expiry ticks, not "in 3 seconds". That keeps
      transitions deterministic — expect tests jump time forward instead of
      sleeping — and clients animate countdowns from [expiry - now] without
      trusting their own clocks.

    {[
      Tick.( < ) Tick.zero (Tick.next Tick.zero) (* true *)
    ]} *)

type t [@@deriving bin_io, hash, sexp]

include Comparable.S with type t := t

(** The tick before the first snapshot. *)
val zero : t

val next : t -> t

(** [add t n] is [t] advanced by [n] ticks. Gameplay durations (how long a
    gate stays closed) are tick counts, converted from seconds by whoever
    owns the tick rate. *)
val add : t -> int -> t

(** For tests and debugging output. *)
val of_int : int -> t

val to_int : t -> int
