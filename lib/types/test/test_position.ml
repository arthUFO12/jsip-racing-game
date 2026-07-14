open! Core
open Racing_types

let%expect_test "vector arithmetic for physics and proximity" =
  let a = { Position.x = 3.; y = 4. } in
  let b = { Position.x = 1.; y = -2. } in
  print_s [%sexp (Position.add a b : Position.t)];
  [%expect {| ((x 4) (y 2)) |}];
  print_s [%sexp (Position.sub a b : Position.t)];
  [%expect {| ((x 2) (y 6)) |}];
  print_s [%sexp (Position.scale a ~by:0.5 : Position.t)];
  [%expect {| ((x 1.5) (y 2)) |}];
  print_s [%sexp (Position.distance Position.origin a : float)];
  [%expect {| 5 |}]
;;
