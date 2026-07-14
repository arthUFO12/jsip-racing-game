open! Core
open Racing_types

let player id name =
  { Player.id = Player_id.of_int id
  ; name = ok_exn (Player_name.of_string name)
  }
;;

let%expect_test "a team is, by shape, one driver plus one track player" =
  let robyn = player 1 "Robyn" in
  let arthur = player 2 "Arthur" in
  let team =
    ok_exn
      (Team.create ~id:(Team_id.of_int 7) ~driver:robyn ~track_player:arthur)
  in
  print_s [%sexp (team : Team.t)];
  [%expect
    {| ((id 7) (driver ((id 1) (name Robyn))) (track_player ((id 2) (name Arthur)))) |}];
  (* Role is where you sit in the team, not a stored field. *)
  List.iter [ 1; 2; 3 ] ~f:(fun id ->
    print_s [%sexp (Team.role team (Player_id.of_int id) : Role.t option)]);
  [%expect {|
    (Driver)
    (Track_player)
    ()
    |}]
;;

let%expect_test "the same player can't fill both slots" =
  let robyn = player 1 "Robyn" in
  print_s
    [%sexp
      (Team.create ~id:(Team_id.of_int 8) ~driver:robyn ~track_player:robyn
       : Team.t Or_error.t)];
  [%expect {| (Error ("a team needs two different players" (player 1))) |}]
;;
