(** A point (or displacement) in continuous world coordinates.

    Cars live at [Vec2.t]s and move smoothly; the map's terrain is grid
    based and queried by snapping to a {!Cell.t} with {!Cell.of_vec2}. The
    frame is y-up with the origin at the map's bottom-left corner —
    matching the OCaml [Graphics] window, so client code never flips an
    axis. One world unit spans one grid cell when {!Game_map.cell_size} is
    [1.0]. *)

open! Core

type t =
  { x : float
  ; y : float
  }
[@@deriving sexp, bin_io, compare, equal]

val zero : t
val add : t -> t -> t
val sub : t -> t -> t
val scale : t -> by:float -> t

(** Euclidean distance — proximity queries like {!Map_state.features_near}
    ("gate closing 20 cells ahead"). *)
val distance : t -> t -> float
