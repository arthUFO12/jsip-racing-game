open! Core
open Racing_map
open Racing_types

type t =
  { cell_px : int
  ; ox : int (* pixel origin of the bottom-left cell [origin] *)
  ; oy : int
  ; origin_col : int
  ; origin_row : int
  ; cell_size : float
  }

let create ~origin ~cells ~cell_size ~area_x ~area_y ~area_w ~area_h =
  let cell_px = Int.max 1 (Int.min (area_w / cells) (area_h / cells)) in
  let grid_px = cell_px * cells in
  (* Center the square grid in the (possibly non-square) area. *)
  let ox = area_x + ((area_w - grid_px) / 2) in
  let oy = area_y + ((area_h - grid_px) / 2) in
  { cell_px
  ; ox
  ; oy
  ; origin_col = origin.Cell.col
  ; origin_row = origin.Cell.row
  ; cell_size
  }
;;

let cell_px t = t.cell_px

let cell_origin_px t (cell : Cell.t) =
  ( t.ox + ((cell.col - t.origin_col) * t.cell_px)
  , t.oy + ((cell.row - t.origin_row) * t.cell_px) )
;;

let world_px t (pos : Position.t) =
  let cells_from_origin coord origin =
    (coord /. t.cell_size) -. Float.of_int origin
  in
  let px base cells =
    base + Float.iround_nearest_exn (cells *. Float.of_int t.cell_px)
  in
  ( px t.ox (cells_from_origin pos.x t.origin_col)
  , px t.oy (cells_from_origin pos.y t.origin_row) )
;;

let cell_of_px t ~x ~y =
  (* Floor division (not OCaml's truncate-toward-zero [/]) so a pixel just
     below or left of [origin] gives a negative index the caller rejects,
     rather than folding onto cell 0. *)
  let floor_div a b = if a >= 0 then a / b else -(((-a) + b - 1) / b) in
  { Cell.col = t.origin_col + floor_div (x - t.ox) t.cell_px
  ; row = t.origin_row + floor_div (y - t.oy) t.cell_px
  }
;;
