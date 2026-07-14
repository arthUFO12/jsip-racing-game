open! Core
open Racing_map
open Racing_types
module Render = Jsip_client_render.Render
module Prim = Jsip_client_render.Prim
module Palette = Jsip_client_render.Palette
module Camera = Jsip_client_render.Camera

(* The palette is the whole art direction in one table, so pin it down: every
   surface, in every theme zone, maps to a chosen colour. *)
let%expect_test "ground palette covers every surface x environment" =
  List.iter Environment.all ~f:(fun environment ->
    List.iter Surface.all ~f:(fun surface ->
      printf
        !"%-7s %-6s -> %{sexp:Prim.Color.t}\n"
        (Sexp.to_string (Environment.sexp_of_t environment))
        (Sexp.to_string (Surface.sexp_of_t surface))
        (Palette.ground ~surface ~environment)));
  [%expect
    {|
    Forest  Road   -> #b69264
    Forest  Wall   -> #7c766c
    Forest  Trees  -> #4c723e
    Castle  Road   -> #a29e98
    Castle  Wall   -> #747080
    Castle  Trees  -> #4e6842
    Cave    Road   -> #625c6a
    Cave    Wall   -> #2e2c38
    Cave    Trees  -> #364e32
    |}]
;;

let%expect_test "camera maps cells and world positions to pixels (y-up)" =
  let cam =
    Camera.create
      ~origin:{ Cell.col = 0; row = 0 }
      ~cells:3
      ~cell_size:1.0
      ~area_x:0
      ~area_y:0
      ~area_w:300
      ~area_h:300
  in
  printf "cell_px = %d\n" (Camera.cell_px cam);
  let cx, cy = Camera.cell_origin_px cam { Cell.col = 1; row = 2 } in
  printf "cell (1,2) bottom-left px = (%d, %d)\n" cx cy;
  let wx, wy = Camera.world_px cam { Position.x = 1.5; y = 1.5 } in
  printf "world (1.5,1.5) px = (%d, %d)\n" wx wy;
  [%expect
    {|
    cell_px = 100
    cell (1,2) bottom-left px = (100, 200)
    world (1.5,1.5) px = (150, 150)
    |}]
;;

(* A hand-built frame: a 3x3 slice spanning all three zones, a collapsed
   bridge (a gap), and the local driver mid-boost. We don't assert every
   pixel — we assert the frame's *shape*: how many of each primitive it emits
   and exactly what text lands in the HUD. *)
let viewport : Map_state.Viewport.t =
  { origin = { Cell.col = 0; row = 0 }
  ; surfaces =
      [| [| Surface.Road; Surface.Road; Surface.Road |]
       ; [| Surface.Trees; Surface.Road; Surface.Wall |]
       ; [| Surface.Trees; Surface.Road; Surface.Trees |]
      |]
  ; environments =
      [| [| Environment.Forest; Environment.Forest; Environment.Forest |]
       ; [| Environment.Forest; Environment.Castle; Environment.Cave |]
       ; [| Environment.Forest; Environment.Forest; Environment.Forest |]
      |]
  ; features =
      [ { Feature.id = Feature_id.of_int 1
        ; cells = [ { Cell.col = 1; row = 0 } ]
        ; payload =
            Feature.Payload.Bridge
              { Feature.Bridge.phase =
                  Feature.Bridge.Phase.Collapsed
                    { rebuilt_at = Tick.of_int 100 }
              }
        }
      ]
  ; is_dark = false
  }
;;

let self_car : Render.Car.t =
  { pos = { Position.x = 1.5; y = 1.5 }
  ; heading = Heading.zero
  ; team = Team_id.of_int 0
  ; is_self = true
  ; effects =
      [ { Effect.kind = Effect.Kind.Powerup Powerup.Speed_boost
        ; remaining = Time_ns.Span.of_sec 3.
        }
      ]
  }
;;

let frame : Render.Frame.t =
  { viewport
  ; cell_size = 1.0
  ; cars = [ self_car ]
  ; track_name = "Dragon's Breath Raceway"
  ; lap = 2
  ; laps_to_win = 3
  ; speed = Some (Speed.of_float_exn 42.)
  ; place = Some 1
  ; time_elapsed = None
  ; window_w = 640
  ; window_h = 480
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

let%expect_test "scene has the expected primitive mix and HUD copy" =
  let scene = Render.scene_of_frame frame in
  printf "primitives: %d\n\n" (List.length scene);
  List.map scene ~f:kind_of
  |> List.sort ~compare:String.compare
  |> List.group ~break:String.( <> )
  |> List.iter ~f:(fun group ->
    printf "  %-12s x %d\n" (List.hd_exn group) (List.length group));
  printf "\nHUD text:\n";
  List.filter_map scene ~f:text_of |> List.iter ~f:(printf "  %S\n");
  [%expect
    {|
    primitives: 100

      Fill_ellipse x 23
      Fill_poly    x 12
      Fill_rect    x 24
      Line         x 31
      Rect         x 5
      Text         x 5

    HUD text:
      "LAP 2/3"
      "POS"
      "1st"
      "Dragon's Breath Raceway"
      "SPD 42"
    |}]
;;
