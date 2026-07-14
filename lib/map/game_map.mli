(** The immutable track layout: surface and environment grids, checkpoint
    order, start grid, and the initial placement of every authored
    feature. A [t] never changes once loaded — everything that changes
    during a race lives in {!Map_state.t}. The server sends [t] to each
    client once at join (hence [bin_io]); both sides query it for the
    static base layer.

    Maps are human-authored sexp files (schema and a worked example live
    in [doc/map-design.md]), so {!load} validates before believing:
    - both grids are rectangular, nonempty, and the same dimensions;
    - checkpoint indexes are exactly [0 .. n-1] with [n >= 2], their cells
      on [Road];
    - every checkpoint is BFS-reachable from the previous one (and
      checkpoint 1 from every start slot) over non-solid cells with every
      gate closed, every bridge collapsed, and every stalactite fallen —
      so no combination of sabotage can make a lap impossible;
    - start slots lie on [Road];
    - feature footprints are nonempty, non-overlapping, and on [Road];
      stalactites hang only over [Cave] cells; ice patches cannot be
      authored (they are spawned in play). *)

open! Core

type t [@@deriving sexp_of, bin_io]

(** {2 Loading} *)

val load : Sexp.t -> t Or_error.t
val load_file_exn : string -> t

(** {2 Metadata} *)

val name : t -> string
val laps_to_win : t -> int

(** World units per cell side (usually [1.0]) — the scale between
    {!Vec2.t} car space and {!Cell.t} grid space. *)
val cell_size : t -> float

val cols : t -> int
val rows : t -> int

(** {2 The static base layer}

    Gameplay code usually wants {!Map_state.surface_at} instead, which
    composes dynamic features (closed gates, debris) over this. *)

(** Total: out-of-grid cells are [Wall], so nothing downstream
    special-cases the edge of the world. *)
val base_surface_at : t -> Cell.t -> Surface.t

(** Total, like {!base_surface_at}; out-of-grid cells report [Forest]
    (arbitrary — they are all [Wall], and never render). *)
val environment_at : t -> Cell.t -> Environment.t

(** {!Cell.of_vec2} with this map's {!cell_size}. *)
val cell_at : t -> Vec2.t -> Cell.t

(** {2 Racing furniture} *)

(** Slot [i] holds the checkpoint with [index = i]. *)
val checkpoints : t -> Checkpoint.t array

(** [Some i] when the cell is part of checkpoint [i] — the game loop's
    per-tick crossing test, fed to {!Checkpoint.Progress.on_touch}. *)
val checkpoint_at : t -> Cell.t -> int option

(** Where cars line up at race start, in starting order. *)
val start_grid : t -> Pose.t list

(** {2 Features} *)

(** Every authored feature in its rest phase — the seed for
    {!Map_state.create}. Live phases belong to {!Map_state}, never
    here. *)
val initial_features : t -> Feature.t list
