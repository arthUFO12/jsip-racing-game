open! Core
open Racing_types
module Prim = Jsip_client_render.Prim
module Hud = Jsip_client_hud.Hud

(* We never open a window: each widget is a pure [Prim.t list], so we assert
   its *shape* — how many of each primitive it emits (the histogram) and
   every string of copy it lays down (the [Text]s). Same idiom as
   [app/client/render/test/test_render.ml]. *)

let kind_of prim =
  match Prim.sexp_of_t prim with
  | Sexp.List (Sexp.Atom name :: _) -> name
  | Sexp.Atom name -> name
  | Sexp.List _ -> "?"
;;

let text_of (prim : Prim.t) =
  match prim with
  | Text { s; _ } -> Some s
  | Fill_rect _ | Rect _ | Fill_poly _ | Fill_ellipse _ | Line _ -> None
;;

let report scene =
  printf "primitives: %d\n" (List.length scene);
  List.map scene ~f:kind_of
  |> List.sort ~compare:String.compare
  |> List.group ~break:String.( <> )
  |> List.iter ~f:(fun group ->
    printf "  %-12s x %d\n" (List.hd_exn group) (List.length group));
  let texts = List.filter_map scene ~f:text_of in
  if not (List.is_empty texts)
  then (
    printf "text:\n";
    List.iter texts ~f:(printf "  %S\n"))
;;

let standings =
  [ { Hud.Standing.place = 2
    ; name = "Bob"
    ; team = Team_id.of_int 1
    ; laps = 2
    }
  ; { Hud.Standing.place = 1
    ; name = "Alice"
    ; team = Team_id.of_int 0
    ; laps = 3
    }
  ; { Hud.Standing.place = 3
    ; name = "Cara"
    ; team = Team_id.of_int 3
    ; laps = 1
    }
  ]
;;

let%expect_test "countdown: number ring, then GO!" =
  report (Hud.countdown ~count:3 ~window_w:640 ~window_h:480);
  printf "\n--- GO ---\n";
  report (Hud.countdown ~count:0 ~window_w:640 ~window_h:480);
  [%expect
    {|
    primitives: 4
      Fill_ellipse x 2
      Fill_rect    x 1
      Text         x 1
    text:
      "3"

    --- GO ---
    primitives: 4
      Fill_ellipse x 2
      Fill_rect    x 1
      Text         x 1
    text:
      "GO!"
    |}]
;;

let%expect_test "finish_board: sorted rows, winner highlighted, ordinals" =
  (* Places chosen to exercise every ordinal branch: st/nd/rd, the 11-13 "th"
     exception, and 21 -> "st". *)
  let ordinal_probe =
    [ { Hud.Standing.place = 21
      ; name = "U"
      ; team = Team_id.of_int 2
      ; laps = 0
      }
    ; { Hud.Standing.place = 3
      ; name = "C"
      ; team = Team_id.of_int 2
      ; laps = 0
      }
    ; { Hud.Standing.place = 11
      ; name = "K"
      ; team = Team_id.of_int 2
      ; laps = 0
      }
    ; { Hud.Standing.place = 2
      ; name = "B"
      ; team = Team_id.of_int 2
      ; laps = 0
      }
    ; { Hud.Standing.place = 1
      ; name = "A"
      ; team = Team_id.of_int 2
      ; laps = 0
      }
    ]
  in
  report (Hud.finish_board ordinal_probe ~window_w:640 ~window_h:480);
  [%expect
    {|
    primitives: 29
      Fill_rect    x 7
      Rect         x 6
      Text         x 16
    text:
      "FINISH"
      "1st"
      "A"
      "0 laps"
      "2nd"
      "B"
      "0 laps"
      "3rd"
      "C"
      "0 laps"
      "11th"
      "K"
      "0 laps"
      "21st"
      "U"
      "0 laps"
    |}]
;;

let%expect_test "leaderboard: compact rows, name truncated" =
  let with_long_name =
    { Hud.Standing.place = 4
    ; name = "Bartholomew the Bold"
    ; team = Team_id.of_int 4
    ; laps = 1
    }
    :: standings
  in
  report (Hud.leaderboard with_long_name ~x:20 ~y:400);
  [%expect
    {|
    primitives: 22
      Fill_rect    x 5
      Rect         x 5
      Text         x 12
    text:
      "1st"
      "Alice"
      "L3"
      "2nd"
      "Bob"
      "L2"
      "3rd"
      "Cara"
      "L1"
      "4th"
      "Bartholomew."
      "L1"
    |}]
;;

let%expect_test "inventory_bar: one tile per powerup, distinct glyphs" =
  let items =
    [ Powerup.Speed_boost, 2; Powerup.Glider, 1; Powerup.Axe, 1 ]
  in
  report (Hud.inventory_bar items ~x:20 ~y:20);
  printf "\n--- all six powerups (glyph coverage) ---\n";
  report
    (Hud.inventory_bar (List.map Powerup.all ~f:(fun p -> p, 1)) ~x:0 ~y:0);
  [%expect
    {|
    primitives: 16
      Fill_poly    x 2
      Fill_rect    x 3
      Line         x 5
      Rect         x 3
      Text         x 3
    text:
      "x2"
      "x1"
      "x1"

    --- all six powerups (glyph coverage) ---
    primitives: 29
      Fill_poly    x 5
      Fill_rect    x 7
      Line         x 5
      Rect         x 6
      Text         x 6
    text:
      "x1"
      "x1"
      "x1"
      "x1"
      "x1"
      "x1"
    |}]
;;

let%expect_test "effect_chips: coloured by kind, integer seconds" =
  let effects =
    [ { Effect.kind = Effect.Kind.Powerup Powerup.Speed_boost
      ; remaining = Time_ns.Span.of_sec 3.4
      }
    ; { Effect.kind = Effect.Kind.Vines; remaining = Time_ns.Span.of_sec 5. }
    ; { Effect.kind = Effect.Kind.Mud_bomb
      ; remaining = Time_ns.Span.of_sec 1.9
      }
    ]
  in
  report (Hud.effect_chips effects ~x:20 ~y:60);
  [%expect
    {|
    primitives: 9
      Fill_rect    x 3
      Rect         x 3
      Text         x 3
    text:
      "Boost 3s"
      "Vines 5s"
      "Mud 1s"
    |}]
;;
