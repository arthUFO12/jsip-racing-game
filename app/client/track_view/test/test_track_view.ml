open! Core
open Racing_types
open Racing_map
module Track_view = Jsip_client_track_view.Track_view
module Prim = Jsip_client_render.Prim

(* The real authored example map, copied next to the test by the dune rule. *)
let game_map = Game_map.load_file_exn "castle_run.sexp"
let track = Map_state.create game_map

let car ~x ~y ~heading ~team ~name ~laps ~own : Track_view.Car_view.t =
  { position = { Position.x; y }
  ; velocity =
      { Velocity.heading = Heading.of_radians_exn heading
      ; speed = Speed.of_float_exn 12.
      }
  ; team = Team_id.of_int team
  ; name
  ; laps_completed = laps
  ; is_own_driver = own
  }
;;

(* A hand-built console frame: the co-pilot's own driver on the start line,
   two rivals out on the course, a stock with duplicates, and a sabotage
   cursor. *)
let frame : Track_view.Frame.t =
  { game_map
  ; track
  ; cars =
      [ car
          ~x:23.5
          ~y:3.5
          ~heading:1.5708
          ~team:0
          ~name:"Alice"
          ~laps:1
          ~own:true
      ; car
          ~x:12.5
          ~y:12.5
          ~heading:3.14159
          ~team:1
          ~name:"Bob"
          ~laps:0
          ~own:false
      ; car
          ~x:5.5
          ~y:2.5
          ~heading:0.0
          ~team:2
          ~name:"Cara"
          ~laps:2
          ~own:false
      ]
  ; inventory =
      [ Powerup.Speed_boost
      ; Powerup.Speed_boost
      ; Powerup.Glider
      ; Powerup.Flashlight
      ; Powerup.Flashlight
      ; Powerup.Flashlight
      ]
  ; race_status = Race_status.Racing
  ; selected = Some { Cell.col = 12; row = 12 }
  ; window_w = 1000
  ; window_h = 640
  }
;;

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

(* We don't assert every pixel — we assert the frame's *shape*: how many of
   each primitive it emits and exactly what text lands in the panel. All
   [Text] in a console scene is panel copy (cars carry no labels), so
   printing every [Text] string is the panel contents. *)
let%expect_test "console scene: primitive mix and panel copy" =
  let scene = Track_view.scene_of_frame frame in
  printf "primitives: %d\n\n" (List.length scene);
  List.map scene ~f:kind_of
  |> List.sort ~compare:String.compare
  |> List.group ~break:String.( <> )
  |> List.iter ~f:(fun group ->
    printf "  %-12s x %d\n" (List.hd_exn group) (List.length group));
  printf "\npanel text:\n";
  List.filter_map scene ~f:text_of |> List.iter ~f:(printf "  %S\n");
  [%expect
    {|
    primitives: 445

      Fill_ellipse x 4
      Fill_poly    x 11
      Fill_rect    x 396
      Line         x 19
      Rect         x 5
      Text         x 10

    panel text:
      "castle-run"
      "RACING"
      "ITEMS"
      "x2"
      "x1"
      "x3"
      "THREATS"
      "Bridge: intact"
      "Gate: open"
      "Stalactite: hanging"
    |}]
;;

(* Focused: duplicate powerups collapse to one row each, carrying an "xN"
   count. Six items over three distinct kinds => three "xN" rows. *)
let%expect_test "inventory counts collapse duplicates into one row per item" =
  let inventory =
    [ Powerup.Speed_boost
    ; Powerup.Speed_boost
    ; Powerup.Speed_boost
    ; Powerup.Glider
    ; Powerup.Glider
    ; Powerup.Axe
    ]
  in
  let scene = Track_view.scene_of_frame { frame with inventory } in
  let count_rows =
    List.filter_map scene ~f:text_of
    |> List.filter ~f:(fun s -> String.is_prefix s ~prefix:"x")
  in
  printf
    "distinct rows: %d (from %d items)\n"
    (List.length count_rows)
    (List.length inventory);
  List.iter count_rows ~f:(printf "  %S\n");
  [%expect
    {|
    distinct rows: 3 (from 6 items)
      "x3"
      "x2"
      "x1"
    |}]
;;
