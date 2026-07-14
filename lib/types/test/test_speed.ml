open! Core
open Racing_types

let show float = print_s [%sexp (Speed.of_float float : Speed.t Or_error.t)]

let%expect_test "speeds are non-negative and finite" =
  show 12.5;
  [%expect {| (Ok 12.5) |}];
  show 0.;
  [%expect {| (Ok 0) |}];
  (* Reverse is a flipped heading, not a negative speed. *)
  show (-3.);
  [%expect
    {| (Error ("speed must be finite and non-negative" (speed -3))) |}];
  show Float.nan;
  [%expect
    {| (Error ("speed must be finite and non-negative" (speed NAN))) |}]
;;
