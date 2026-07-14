open! Core

(** A point (or displacement) in continuous world space, in game units. Cars
    live at positions and move smoothly; the map's terrain is a grid, queried
    by snapping a position to a cell ([Racing_map.Cell.of_position]). The
    frame is y-up with the origin at the map's bottom-left corner — matching
    the OCaml [Graphics] window, so client code never flips an axis. One
    world unit spans one grid cell when the map's cell size is [1.0].

    What is {e at} a position (road, bridge, a gap) is the map library's
    business, not this module's. These floats are machine data (server
    physics output, map-file loading), so unlike {!Player_name} there is no
    human-input validation here. *)

type t =
  { x : float
  ; y : float
  }
[@@deriving bin_io, compare, equal, sexp]

val origin : t
val add : t -> t -> t
val sub : t -> t -> t
val scale : t -> by:float -> t

(** Euclidean distance — proximity queries like "is that gate closing near my
    car?". *)
val distance : t -> t -> float
