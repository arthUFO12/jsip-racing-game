(** Integer grid coordinates. [col] counts from the left edge, [row] from
    the BOTTOM edge (y-up, matching {!Vec2} and the OCaml [Graphics]
    window). {!Vec2.t} is car space, [Cell.t] is terrain space; {!of_vec2}
    is the bridge between them. *)

open! Core

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
val of_vec2 : Vec2.t -> cell_size:float -> t

(** The center of the cell in world coordinates — where spawned features
    (ice patches) anchor and where the client draws cell-sized sprites. *)
val center : t -> cell_size:float -> Vec2.t

(** Cells whose centers lie within [radius] world units of [center]: the
    footprint helper behind ice-patch placement and
    {!Map_state.features_near}. *)
val in_radius : center:Vec2.t -> radius:float -> cell_size:float -> t list
