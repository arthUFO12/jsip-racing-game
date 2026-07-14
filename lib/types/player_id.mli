open! Core

(** A globally unique identifier for one player, assigned by the server when
    the player joins (see [join_game_rpc] in [doc/rpc-protocol.md]). Every
    update between client and server is tagged with one of these, and all
    per-player server state is keyed by it.

    The type is abstract on purpose: even though it is an integer underneath,
    the compiler will stop you from confusing a player id with a
    {!Team_id.t}, a lap count, or any other stray [int].

    Example — the server keying per-driver state by id:

    {[
      let latest_inputs : Driver_input.t Player_id.Map.t =
        Player_id.Map.empty
      ;;
    ]} *)

type t [@@deriving hash, sexp]

include Comparable.S with type t := t
include Hashable.S with type t := t

(** [of_int] exists for the server-side id allocator and for tests. Clients
    never invent ids; they use the one the server handed out at join time. *)
val of_int : int -> t

val to_int : t -> int
