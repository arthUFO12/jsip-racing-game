(** Identifies one {!Feature.t} for the whole race — the handle a track
    player's sabotage names ("collapse bridge 3", {!Track_action}).
    {!Game_map.load} assigns ids to authored features; {!Map_state}
    allocates fresh ones when a track player spawns an ice patch. *)

open! Core

type t [@@deriving sexp, bin_io, compare, equal, hash]

(*_ [S_binable] rather than [S] so [Feature_id.Map.t] can ride inside
    [Map_state.t] across the wire. *)
include Comparable.S_binable with type t := t
include Hashable.S with type t := t

val of_int : int -> t
val to_int : t -> int
