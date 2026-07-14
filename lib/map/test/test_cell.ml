open! Core
open Racing_types
open Racing_map

let%expect_test "positions snap to the containing cell" =
  let cell_of x y = Cell.of_position { Position.x; y } ~cell_size:1.0 in
  print_s [%sexp (cell_of 0.5 0.5 : Cell.t)];
  [%expect {| ((col 0) (row 0)) |}];
  print_s [%sexp (cell_of 3.99 2.0 : Cell.t)];
  [%expect {| ((col 3) (row 2)) |}];
  (* Off-map positions still snap to a (nonexistent) cell; the map layer
     reads those as [Wall] rather than anyone bounds-checking here. *)
  print_s [%sexp (cell_of (-0.1) 7.5 : Cell.t)];
  [%expect {| ((col -1) (row 7)) |}]
;;

let%expect_test "center is the middle of the cell, in world units" =
  print_s
    [%sexp
      (Cell.center { Cell.col = 2; row = 0 } ~cell_size:1.0 : Position.t)];
  [%expect {| ((x 2.5) (y 0.5)) |}]
;;

let%expect_test "in_radius is a disc of cells, not the bounding square" =
  let cells =
    Cell.in_radius
      ~center:{ Position.x = 2.5; y = 2.5 }
      ~radius:1.0
      ~cell_size:1.0
  in
  print_s [%sexp (cells : Cell.t list)];
  [%expect
    {|
    (((col 2) (row 1)) ((col 1) (row 2)) ((col 2) (row 2)) ((col 3) (row 2))
     ((col 2) (row 3)))
    |}]
;;
