open! Core
open Racing_types

let%expect_test "ticks are monotonic so clients can drop stale snapshots" =
  let t0 = Tick.zero in
  let t1 = Tick.next t0 in
  let t2 = Tick.next t1 in
  print_s [%sexp ([ t0; t1; t2 ] : Tick.t list)];
  [%expect {| (0 1 2) |}];
  let is_newer snapshot ~than = Tick.( > ) snapshot than in
  print_s [%sexp (is_newer t2 ~than:t1 : bool)];
  [%expect {| true |}];
  print_s [%sexp (is_newer t1 ~than:t2 : bool)];
  [%expect {| false |}]
;;
