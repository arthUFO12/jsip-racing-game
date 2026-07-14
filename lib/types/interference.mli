open! Core

(** Everything a track player can invoke against other teams — the payload of
    [use_interference_rpc] in [doc/rpc-protocol.md]. Each constructor carries
    exactly the target it needs and nothing else: ice can't name a victim,
    vines can't miss theirs.

    Track-targeted interference from the brainstorm (collapsing a bridge,
    closing a castle gate, dropping stalactites in a cave) is deliberately
    absent for now: those constructors need the track model
    (bridge/gate/cave-section ids), which is being designed separately. Add
    them here — with their own distinct id types, so a bridge collapse aimed
    at a gate won't typecheck — once it lands.

    An honest limit: [Vines] and [Mud_bomb] carry a {!Player_id.t}, and ids
    don't know which role they belong to — "mud-bomb a track player"
    typechecks. That is the boundary of what these types can enforce, so the
    server validates targets (a driver, not on your own team) and answers
    with an [Or_error.t] ("invalid target" in the protocol doc). Illegal
    states we can't make unrepresentable, we reject at the boundary.

    How long each effect lasts and how strong it is ("X seconds", "X%") are
    game-tuning constants that live with the game rules, not here. *)

type t =
  | Slick_track
  (** the whole track turns slippery for every driver until it melts;
      {!Powerup.Flame_magic} melts it early. (spec.md says track-wide, so no
      payload; rpc-protocol.md sketches a positioned version — revisit with
      the track model.) *)
  | Vines of Player_id.t
  (** slow the target driver until it wears off or an {!Powerup.Axe} cuts it *)
  | Mud_bomb of Player_id.t (** blind the target driver for a while *)
[@@deriving bin_io, compare, equal, sexp_of]
