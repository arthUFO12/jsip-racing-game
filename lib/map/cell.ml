open! Core

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

let of_vec2 (v : Vec2.t) ~cell_size =
  { col = Float.iround_down_exn (v.x /. cell_size)
  ; row = Float.iround_down_exn (v.y /. cell_size)
  }
;;

let center t ~cell_size =
  { Vec2.x = (Float.of_int t.col +. 0.5) *. cell_size
  ; y = (Float.of_int t.row +. 0.5) *. cell_size
  }
;;

let in_radius ~center:(around : Vec2.t) ~radius ~cell_size =
  let corner = { Vec2.x = radius; y = radius } in
  let lo = of_vec2 (Vec2.sub around corner) ~cell_size in
  let hi = of_vec2 (Vec2.add around corner) ~cell_size in
  List.concat_map (List.range lo.row (hi.row + 1)) ~f:(fun row ->
    List.filter_map (List.range lo.col (hi.col + 1)) ~f:(fun col ->
      let cell = { col; row } in
      let distance = Vec2.distance (center cell ~cell_size) around in
      match Float.( <= ) distance radius with
      | true -> Some cell
      | false -> None))
;;
