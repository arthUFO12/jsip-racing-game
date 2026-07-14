(** One dynamic map feature: a bridge, castle gate, stalactite cluster, or
    ice patch — the things a track player can sabotage and a driver must
    survive. The {!Payload} variant carries BOTH the per-kind parameters
    and the current phase, so an ill-typed pairing (a gate in a bridge
    phase) is unrepresentable and there is no separate state table to
    drift out of sync.

    Timed phases store the absolute {!Tick.t} at which they end. Hostile
    transitions all pass through a telegraph phase ([Collapsing],
    [Closing], [Falling]) that is still safe to drive — that window is
    what a co-pilot watches for to warn their driver. Transitions
    themselves live in {!Map_state}; this module only defines shapes and
    per-feature facts. *)

open! Core

module Bridge : sig
  (** Spans a break in the track. While [Collapsed] its cells are a gap
      ({!is_gap}): physics lets gliding cars cross and drops the rest.
      Auto-rebuilds, so a lap never becomes permanently impossible. *)
  module Phase : sig
    type t =
      | Intact
      | Collapsing of { falls_at : Tick.t }
      (** telegraph: shaking, still drivable *)
      | Collapsed of { rebuilt_at : Tick.t } (** a gap in the track *)
    [@@deriving sexp, bin_io, compare, equal]
  end

  type t = { phase : Phase.t } [@@deriving sexp, bin_io, compare, equal]
end

module Gate : sig
  (** A castle portcullis on a chokepoint. While [Closed] its cells are
      solid [Wall]: drivers brake or take the branch route map authors
      guarantee exists ({!Game_map.load} validation). Reopens on a
      timer. *)
  module Phase : sig
    type t =
      | Open
      | Closing of { shut_at : Tick.t }
      (** telegraph: descending, still passable *)
      | Closed of { reopens_at : Tick.t }
    [@@deriving sexp, bin_io, compare, equal]
  end

  type t = { phase : Phase.t } [@@deriving sexp, bin_io, compare, equal]
end

module Stalactite : sig
  (** A cave-ceiling trap. Triggering it drops it: cars under it when it
      lands are the game loop's problem (stun); the [Debris] then blocks
      the cells like a wall until it clears and the trap re-arms. *)
  module Phase : sig
    type t =
      | Hanging
      | Falling of { lands_at : Tick.t }
      (** telegraph: dust and a growing shadow *)
      | Debris of { cleared_at : Tick.t } (** solid rubble on the road *)
    [@@deriving sexp, bin_io, compare, equal]
  end

  type t = { phase : Phase.t } [@@deriving sexp, bin_io, compare, equal]
end

module Ice_patch : sig
  (** A slick a track player pours on open road; drops every car's
      traction on its cells. Existence IS the state: the patch leaves
      {!Map_state} entirely ([Update.Removed]) when it melts — on its
      timer, or early when a driver counters it with flame magic. *)
  type t = { melts_at : Tick.t } [@@deriving sexp, bin_io, compare, equal]
end

module Payload : sig
  type t =
    | Bridge of Bridge.t
    | Gate of Gate.t
    | Stalactite of Stalactite.t
    | Ice_patch of Ice_patch.t
  [@@deriving sexp, bin_io, compare, equal]
end

module Kind : sig
  (** The payload-free tag: UI ability lists and {!Track_action}
      validation. This is the ONLY mirror of {!Payload.t}; {!val:kind} is
      the single bridge between them, and the no-catch-all-match house
      rule means adding a payload constructor breaks the build until every
      consumer decides what the new kind does. *)
  type t =
    | Bridge
    | Gate
    | Stalactite
    | Ice_patch
  [@@deriving sexp, bin_io, compare, equal, enumerate]
end

type t =
  { id : Feature_id.t
  ; cells : Cell.t list
  (** footprint on the grid; nonempty and all-[Road], validated at
      load/spawn time *)
  ; payload : Payload.t
  }
[@@deriving sexp, bin_io, compare, equal]

val kind : t -> Kind.t

(** {2 Composed-terrain facts}

    How {!Map_state} folds features into the base grid. They live here so
    that adding a phase forces (via exhaustive matches) a decision about
    how it drives. *)

(** [Some Wall] while the feature makes its cells solid: a [Closed] gate,
    settled [Debris]. [None] whenever the base surface shows through —
    telegraph phases included; they stay drivable. *)
val surface_override : t -> Surface.t option

(** True while the feature's cells are a hole in the track — a bridge in
    [Collapsed]. The map reports the hole; physics decides who falls
    (gliders cross). *)
val is_gap : t -> bool

(** The grip multiplier the feature contributes on its cells: [< 1.0] for
    an ice patch (provisional tuning constant in [feature.ml]), [1.0] for
    everything else. {!Map_state.traction_at} multiplies these together. *)
val traction_multiplier : t -> float
