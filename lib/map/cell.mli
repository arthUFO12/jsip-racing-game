(** Integer grid coordinates. [col] counts from the left edge, [row] from the
    BOTTOM edge (y-up, matching {!Racing_types.Position} and the OCaml
    [Graphics] window). [Position.t] is car space, [Cell.t] is terrain space;
    {!of_position} is the bridge between them. *)

open! Core
open Racing_types

type t =
  { col : int
  ; row : int
  }
[@@deriving sexp, bin_io, compare, equal, hash]

include Comparable.S with type t := t
include Hashable.S with type t := t

(** The cell containing this world position. Total: positions off the map
    still snap to (out-of-range) cells, which {!Game_map.base_surface_at}
    reports as [Wall] — so callers never special-case the world's edge. *)
val of_position : Position.t -> cell_size:float -> t

(** The center of the cell in world coordinates — where spawned features (ice
    patches) anchor and where the client draws cell-sized sprites. *)
val center : t -> cell_size:float -> Position.t

(** Cells whose centers lie within [radius] world units of [center]: the
    footprint helper behind ice-patch placement and
    {!Map_state.features_near}. *)
val in_radius
  :  center:Position.t
  -> radius:float
  -> cell_size:float
  -> t list
