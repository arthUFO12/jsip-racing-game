open! Core
open Racing_types

module T = struct
  type t =
    { col : int
    ; row : int
    }
  [@@deriving sexp, bin_io, compare, equal, hash]
end

include T
include Comparable.Make (T)
include Hashable.Make (T)

let of_position (position : Position.t) ~cell_size =
  { col = Float.iround_down_exn (position.x /. cell_size)
  ; row = Float.iround_down_exn (position.y /. cell_size)
  }
;;

let center t ~cell_size =
  { Position.x = (Float.of_int t.col +. 0.5) *. cell_size
  ; y = (Float.of_int t.row +. 0.5) *. cell_size
  }
;;

let in_radius ~center:(around : Position.t) ~radius ~cell_size =
  let corner = { Position.x = radius; y = radius } in
  let lo = of_position (Position.sub around corner) ~cell_size in
  let hi = of_position (Position.add around corner) ~cell_size in
  List.concat_map
    (List.range lo.row (hi.row + 1))
    ~f:(fun row ->
      List.filter_map
        (List.range lo.col (hi.col + 1))
        ~f:(fun col ->
          let cell = { col; row } in
          let distance = Position.distance (center cell ~cell_size) around in
          match Float.( <= ) distance radius with
          | true -> Some cell
          | false -> None))
;;
