open! Core
open Racing_types

let show radians =
  print_s [%sexp (Heading.of_radians radians : Heading.t Or_error.t)]
;;

let%expect_test "headings always land in the normalized range" =
  show 0.;
  [%expect {| (Ok 0) |}];
  show Float.pi;
  [%expect {| (Ok 3.1415926535897931) |}];
  (* Negative angles wrap around to the equivalent positive one. *)
  show (-.Float.pi /. 2.);
  [%expect {| (Ok 4.71238898038469) |}];
  (* Extra full turns are folded away. *)
  show (5. *. Float.pi);
  [%expect {| (Ok 3.1415926535897931) |}];
  show (2. *. Float.pi);
  [%expect {| (Ok 0) |}]
;;

let%expect_test "junk floats are rejected, since clients can send anything" =
  show Float.nan;
  [%expect {| (Error ("heading must be a finite angle" (radians NAN))) |}];
  show Float.infinity;
  [%expect {| (Error ("heading must be a finite angle" (radians INF))) |}]
;;
