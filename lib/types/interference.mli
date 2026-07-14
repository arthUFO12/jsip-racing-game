open! Core

(** The powerdowns a track player aims at one rival driver — the
    car-targeting half of sabotage. The other half, altering the track itself
    (collapsing bridges, closing gates, dropping stalactites, pouring ice),
    lives in [Racing_map.Track_action]: it needs the track model, and this
    library sits below the map. Neither half can name the other, so the
    protocol — above both — unions them for [use_interference_rpc] (see
    [doc/rpc-protocol.md]) rather than either library re-listing the other's
    constructors.

    (Ice used to be a payload-less [Slick_track] placeholder here, from
    before the track model existed. It is now [Track_action.Place_ice] — a
    real located ice patch — so keeping [Slick_track] would just duplicate
    it.)

    An honest limit: the target is a bare {!Player_id.t}, and ids don't know
    which role they belong to — "mud-bomb a track player" typechecks. That is
    the boundary of what these types can enforce, so the server validates the
    target (a driver, not on your own team) and answers with an [Or_error.t]
    ("invalid target" in the protocol doc). Illegal states we can't make
    unrepresentable, we reject at the boundary.

    How long each effect lasts and how strong it is ("X seconds", "X%") are
    game-tuning constants that live with the game rules, not here. *)

type t =
  | Vines of Player_id.t
  (** slow the target driver until it wears off or an {!Powerup.Axe} cuts it *)
  | Mud_bomb of Player_id.t (** blind the target driver for a while *)
[@@deriving bin_io, compare, equal, sexp_of]
