open! Core
open Racing_map

let show (progress : Checkpoint.Progress.t) result =
  print_s
    [%sexp
      { progress : Checkpoint.Progress.t
      ; result : [ `Advanced | `Lap_completed | `Ignored ]
      }]
;;

let%expect_test "a lap advances only through the expected checkpoints" =
  let touch progress ~touched =
    Checkpoint.Progress.on_touch progress ~checkpoint_count:4 ~touched
  in
  let progress = Checkpoint.Progress.initial in
  print_s [%sexp (progress : Checkpoint.Progress.t)];
  [%expect {| ((next_index 1) (laps_completed 0)) |}];
  (* cutting the course straight to checkpoint 3 earns nothing *)
  let progress, result = touch progress ~touched:3 in
  show progress result;
  [%expect
    {| ((progress ((next_index 1) (laps_completed 0))) (result Ignored)) |}];
  (* re-touching the start line before finishing the loop earns nothing *)
  let progress, result = touch progress ~touched:0 in
  show progress result;
  [%expect
    {| ((progress ((next_index 1) (laps_completed 0))) (result Ignored)) |}];
  (* the real lap: 1, 2, 3, then the start line completes it *)
  let progress, result = touch progress ~touched:1 in
  show progress result;
  [%expect
    {| ((progress ((next_index 2) (laps_completed 0))) (result Advanced)) |}];
  let progress, result = touch progress ~touched:2 in
  show progress result;
  [%expect
    {| ((progress ((next_index 3) (laps_completed 0))) (result Advanced)) |}];
  let progress, result = touch progress ~touched:3 in
  show progress result;
  [%expect
    {| ((progress ((next_index 0) (laps_completed 0))) (result Advanced)) |}];
  let progress, result = touch progress ~touched:0 in
  show progress result;
  [%expect
    {| ((progress ((next_index 1) (laps_completed 1))) (result Lap_completed)) |}]
;;
