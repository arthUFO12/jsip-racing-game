open! Core

(** Something temporarily acting on one driver, as pushed to clients in every
    snapshot ([effects : Effect.t list Player_id.Map.t] in the
    rpc-protocol.md sketch). {e Whose} effect it is lives in the map key —
    the effect doesn't repeat its owner, so key and value can't disagree.

    [remaining] is a duration rather than an absolute deadline: the server —
    the only clock authority — recomputes it every tick, so a client can
    render "melts in 3s" without sharing a clock with the server.

    Track-wide trouble (a collapsed bridge, a closed gate) is {e not} an
    effect on a driver: it is state of the track itself, tracked once, not
    copied onto every car. *)

module Kind : sig
  type t =
    | Powerup of Powerup.t (** granted by your own track player *)
    | Vines (** slowed by {!Interference.Vines}; {!Powerup.Axe} cuts free *)
    | Mud_bomb (** blinded by {!Interference.Mud_bomb} *)
  [@@deriving bin_io, compare, equal, sexp_of]
end

type t =
  { kind : Kind.t
  ; remaining : Time_ns.Span.t (** server-computed; counts down to zero *)
  }
[@@deriving bin_io, compare, equal, sexp_of]
