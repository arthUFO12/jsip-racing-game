open! Core
open Racing_types

let try_name string =
  print_s [%sexp (Player_name.of_string string : Player_name.t Or_error.t)]
;;

let%expect_test "player names are validated at the edge" =
  try_name "Robyn";
  [%expect {| (Ok Robyn) |}];
  try_name "speedy-racer_2";
  [%expect {| (Ok speedy-racer_2) |}];
  (* Exactly [max_length] characters is fine... *)
  try_name "sixteen_chars_xx";
  [%expect {| (Ok sixteen_chars_xx) |}];
  (* ...one more is not. *)
  try_name "seventeen_charsxx";
  [%expect
    {| (Error ("player name is too long" (name seventeen_charsxx) (max_length 16))) |}];
  try_name "";
  [%expect {| (Error "player name may not be empty") |}];
  try_name "bad name";
  [%expect
    {|
    (Error
     ("player name may only contain letters, digits, '_' and '-'"
      (name "bad name")))
    |}]
;;

let%expect_test "every broken rule is reported, not just the first" =
  try_name "the fastest racer in the forest!";
  [%expect
    {|
    (Error
     (("player name is too long" (name "the fastest racer in the forest!")
       (max_length 16))
      ("player name may only contain letters, digits, '_' and '-'"
       (name "the fastest racer in the forest!"))))
    |}]
;;
