open! Core
open Racing_types

(* [driver_input] is not tested here: it reads live [Graphics] key state via
   [Input.is_pressed], which has no value to drive from a unit test. *)

let show = function
  | None -> "none"
  | Some p -> Sexp.to_string [%sexp (p : Powerup.t)]
;;

let%expect_test "powerup_for_digit: empty inventory" =
  let inventory = [] in
  print_endline (show (Jsip_client.Controls.powerup_for_digit ~inventory ~digit:1));
  [%expect {| none |}]
;;

let%expect_test "powerup_for_digit: 1-indexed slot selection" =
  let inventory = [ Powerup.Speed_boost; Powerup.Glider ] in
  let show_digit digit =
    print_endline
      (show (Jsip_client.Controls.powerup_for_digit ~inventory ~digit))
  in
  show_digit 1;
  [%expect {| Speed_boost |}];
  show_digit 2;
  [%expect {| Glider |}];
  show_digit 3;
  [%expect {| none |}];
  show_digit 0;
  [%expect {| none |}]
;;
