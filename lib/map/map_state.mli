(** The live state of every dynamic feature — the part of the map that
    changes during a race. The server owns the authoritative copy and is
    the only side that transitions it, by applying track-player
    {!Track_action}s and tick timers through the pure functions here.
    Under the protocol in [doc/rpc-protocol.md] the whole [t] rides
    inside every per-tick [Game_snapshot] (hence [bin_io]); clients
    simply render the latest copy.

    Each transition also returns the {!Update.t}s describing what just
    changed. The game loop reacts to those (a stalactite entering
    [Debris] means "stun the cars in its cells"), and they keep a
    delta-based feed possible later without redesign — a client replica
    folding them in with {!apply_update} reproduces the server state
    exactly.

    Terrain queries here are COMPOSED (base grid + feature overlays);
    gameplay and rendering should ask these, not
    {!Game_map.base_surface_at}. *)

open! Core

type t [@@deriving sexp_of, bin_io, equal]

(** Every authored feature in its rest phase: the race-start state, seeded
    from {!Game_map.initial_features}. *)
val create : Game_map.t -> t

module Update : sig
  (** One feature-level change, as produced by a transition. [Set] carries
      the entire resulting feature — idempotent and safe to re-apply — so
      consumers (the game loop today, a delta feed if snapshots ever get
      too fat) never re-run transition rules. *)
  type t =
    | Set of Feature.t (** phase changed, or a fresh spawn (ice) *)
    | Removed of Feature_id.t (** an ice patch melted *)
  [@@deriving sexp, bin_io, compare, equal]
end

(** {2 Server-side transitions}

    All pure — the caller keeps the returned [t] and broadcasts the
    updates. *)

(** Validate and apply one track player's sabotage at tick [now]. Errors
    (with context): unknown id, action/kind mismatch (collapsing a gate),
    feature not in its rest phase (already sabotaged, or mid-telegraph),
    ice placed on cells that are not open road. The server should reject
    just that command — an [Error] is a normal game event, not a crash. *)
val apply_action
  :  t
  -> map:Game_map.t
  -> action:Track_action.t
  -> now:Tick.t
  -> (t * Update.t list) Or_error.t

(** Fire every timer with expiry [<= now]: [Collapsing -> Collapsed],
    [Closed -> Open], [Falling -> Debris], melted ice -> [Removed], and
    so on. The game loop should check for cars standing in the cells of
    any feature that just entered [Debris] (stun them) or [Collapsed]
    (they fall unless gliding). *)
val tick : t -> now:Tick.t -> t * Update.t list

(** A driver countered an ice patch with flame magic — reported by the
    game loop, which owns item logic. Errors if [id] is not a live ice
    patch. *)
val melt_ice : t -> id:Feature_id.t -> (t * Update.t list) Or_error.t

(** {2 Replaying updates} *)

(** Folding a transition's updates, in order, into a copy of the
    pre-transition [t] reproduces the post-transition [t] exactly
    ([equal] makes that an expect-testable property). Unused by the
    current full-snapshot protocol — kept because it is the whole delta
    story if we ever want one, and it pins down what [Update.t] means. *)
val apply_update : t -> Update.t -> t

(** {2 Composed terrain facts (server physics AND client rendering)} *)

(** {!Game_map.base_surface_at} with feature overlays applied: a [Closed]
    gate or stalactite [Debris] reads as [Wall]. *)
val surface_at : t -> map:Game_map.t -> Vec2.t -> Surface.t

(** [Surface.is_solid] of the composed surface, cell-keyed for physics'
    per-corner sampling loop. *)
val is_blocked : t -> map:Game_map.t -> Cell.t -> bool

(** True on the cells of a bridge in [Collapsed]: a hole in the track. The
    map reports the hole; physics lets gliding cars cross and drops the
    rest (respawn at the last-touched checkpoint is car-side logic). *)
val is_gap : t -> map:Game_map.t -> Cell.t -> bool

(** Product of {!Feature.traction_multiplier} over the features covering
    this position: [1.0] on clean track, [< 1.0] on ice. Physics folds it
    into grip/acceleration. *)
val traction_at : t -> map:Game_map.t -> Vec2.t -> float

val feature : t -> Feature_id.t -> Feature.t option
val features : t -> Feature.t list

(** Features whose footprint intersects the disc — co-pilot warnings
    ("gate closing ahead!") and the client's sprite draw list. *)
val features_near
  :  t
  -> map:Game_map.t
  -> center:Vec2.t
  -> radius:float
  -> Feature.t list

(** {2 The driver's limited view} *)

module Viewport : sig
  (** A renderable slice around one car: composed terrain plus the visible
      features, as pure data. The driver client turns each frame's
      viewport into [Graphics] calls — one [fill_rect] per cell, sprites
      for [features]; nothing here depends on [graphics]. *)
  type t =
    { origin : Cell.t (** bottom-left cell of the slice (y-up) *)
    ; surfaces : Surface.t array array
    (** [surfaces.(r).(c)] describes the cell at
        [{ col = origin.col + c; row = origin.row + r }], composed *)
    ; environments : Environment.t array array
    ; features : Feature.t list (** those intersecting the slice *)
    ; is_dark : bool
    (** the center cell is in a [Cave]; what the flashlight reveals is
        the client's call *)
    }
  [@@deriving sexp_of, bin_io]
end

(** The square slice [2 * half_extent_cells + 1] cells on a side, centered
    on the cell containing [center]. Never clipped: out-of-grid cells read
    [Wall], so the slice is always full size. *)
val viewport
  :  t
  -> map:Game_map.t
  -> center:Vec2.t
  -> half_extent_cells:int
  -> Viewport.t
