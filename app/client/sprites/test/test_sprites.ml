open! Core
open Racing_map
open Racing_types
module Prim = Jsip_client_render.Prim
module Palette = Jsip_client_render.Palette
module Sprites = Jsip_client_sprites.Sprites

(* Derive a primitive's kind (its sexp head atom) so we can summarize a scene
   as a per-kind histogram rather than pinning every coordinate — same idiom
   as app/client/render/test/test_render.ml. *)
let kind_of prim =
  match Prim.sexp_of_t prim with
  | Sexp.List (Sexp.Atom name :: _) -> name
  | Sexp.Atom name -> name
  | Sexp.List _ -> "?"
;;

let histogram prims =
  List.map prims ~f:kind_of
  |> List.sort ~compare:String.compare
  |> List.group ~break:String.( <> )
  |> List.iter ~f:(fun group ->
    printf "    %-12s x %d\n" (List.hd_exn group) (List.length group))
;;

let report name prims =
  printf "%s: %d primitives\n" name (List.length prims);
  histogram prims
;;

(* A sample cell box and a leafy green base, reused across the tile sprites. *)
let box_x = 40
let box_y = 60
let box_size = 32

let leaf_green =
  Palette.ground ~surface:Surface.Trees ~environment:Environment.Forest
;;

let stone =
  Palette.ground ~surface:Surface.Wall ~environment:Environment.Castle
;;

let%expect_test "tile and prop sprites emit sensible primitive mixes" =
  report
    "tree_cluster"
    (Sprites.tree_cluster ~x:box_x ~y:box_y ~size:box_size ~base:leaf_green);
  report
    "brick_wall"
    (Sprites.brick_wall ~x:box_x ~y:box_y ~size:box_size ~base:stone);
  report
    "rock_wall"
    (Sprites.rock_wall ~x:box_x ~y:box_y ~size:box_size ~base:stone);
  report
    "plank_floor"
    (Sprites.plank_floor ~x:box_x ~y:box_y ~size:box_size ~base:leaf_green);
  report
    "banner"
    (Sprites.banner
       ~x:box_x
       ~y:box_y
       ~size:box_size
       ~color:(Prim.Color.rgb 200 58 46));
  report
    "rune_crystal"
    (Sprites.rune_crystal ~x:box_x ~y:box_y ~size:box_size);
  [%expect
    {|
    tree_cluster: 6 primitives
        Fill_ellipse x 5
        Fill_rect    x 1
    brick_wall: 7 primitives
        Fill_rect    x 1
        Line         x 6
    rock_wall: 6 primitives
        Fill_ellipse x 3
        Fill_poly    x 2
        Fill_rect    x 1
    plank_floor: 8 primitives
        Fill_rect    x 1
        Line         x 7
    banner: 4 primitives
        Fill_poly    x 2
        Line         x 2
    rune_crystal: 6 primitives
        Fill_ellipse x 1
        Fill_poly    x 3
        Line         x 2
    |}]
;;

(* Grab every Fill_poly's points; the body is the poly with the most vertices
   (8 vs. the wheels' 4). Its coordinates must move when [heading] changes —
   that is what proves the sprite actually rotates. *)
let poly_points prims =
  List.filter_map prims ~f:(function
    | Prim.Fill_poly { points; _ } -> Some points
    | Fill_rect _ | Rect _ | Fill_ellipse _ | Line _ | Text _ -> None)
;;

let body prims =
  poly_points prims
  |> List.max_elt ~compare:(fun a b ->
    Int.compare (Array.length a) (Array.length b))
  |> Option.value_exn
;;

let%expect_test "car_sprite has the expected mix and rotates with heading" =
  let livery = Prim.Color.rgb 46 107 200 in
  let car heading =
    Sprites.car_sprite
      ~cx:100
      ~cy:100
      ~size:40
      ~heading
      ~livery
      ~number:(Some 7)
  in
  report "car_sprite" (car 0.);
  let p0 = (body (car 0.)).(0) in
  let p90 = (body (car (Float.pi /. 2.))).(0) in
  let ax, ay = p0 in
  let bx, by = p90 in
  printf "\nbody[0] @heading 0    = (%d, %d)\n" ax ay;
  printf "body[0] @heading pi/2 = (%d, %d)\n" bx by;
  printf "rotates = %b\n" (not ([%equal: int * int] p0 p90));
  [%expect
    {|
    car_sprite: 10 primitives
        Fill_ellipse x 3
        Fill_poly    x 6
        Text         x 1

    body[0] @heading 0    = (117, 106)
    body[0] @heading pi/2 = (94, 117)
    rotates = true
    |}]
;;

let%expect_test "minimap renders the real castle_run track" =
  let map = Game_map.load_file_exn "castle_run.sexp" in
  let track = Map_state.create map in
  let cars =
    [ { Position.x = 3.5; y = 4.5 }, Team_id.of_int 0
    ; { Position.x = 12.2; y = 6.8 }, Team_id.of_int 1
    ]
  in
  let scene =
    Sprites.Minimap.render map track ~cars ~x:0 ~y:0 ~w:200 ~h:120
  in
  printf "map: %dx%d cells\n" (Game_map.cols map) (Game_map.rows map);
  report "minimap" scene;
  printf "non_empty = %b\n" (not (List.is_empty scene));
  [%expect
    {|
    map: 26x15 cells
    minimap: 393 primitives
        Fill_ellipse x 2
        Fill_rect    x 390
        Rect         x 1
    non_empty = true
    |}]
;;
