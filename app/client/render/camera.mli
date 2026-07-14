(** Maps the driver's viewport — a square block of grid cells around their
    car — onto a pixel rectangle of the window, with square cells. This is
    the only module that touches the float-world-to-int-pixel conversion;
    drawing code works entirely in the pixels it hands back.

    Both spaces are y-up (see {!Prim}), so a larger grid row is a larger
    pixel [y] — no axis flip. *)

open! Core
open Racing_map
open Racing_types

type t

(** Fit a [cells]-by-[cells] grid whose bottom-left cell is [origin] into the
    pixel area [(area_x, area_y, area_w, area_h)]. Cells are squared to
    [min area_w area_h / cells] and the resulting grid is centered in the
    area, so a non-square area just gets letterboxed rather than stretched.
    [cell_size] is the map's world-units-per-cell
    ({!Racing_map.Game_map.cell_size}). *)
val create
  :  origin:Cell.t
  -> cells:int
  -> cell_size:float
  -> area_x:int
  -> area_y:int
  -> area_w:int
  -> area_h:int
  -> t

(** Side length of one cell, in pixels. *)
val cell_px : t -> int

(** Bottom-left pixel corner of a grid cell. *)
val cell_origin_px : t -> Cell.t -> int * int

(** Pixel location of a continuous world position — where a car actually is,
    sub-cell offset and all. *)
val world_px : t -> Position.t -> int * int

(** Inverse of {!cell_origin_px}: the grid cell a window pixel falls in — used
    for click-to-target on the whole-map console. Pixels below or left of
    [origin] come back with negative indices, so callers can bounds-check
    against the grid. *)
val cell_of_px : t -> x:int -> y:int -> Cell.t
