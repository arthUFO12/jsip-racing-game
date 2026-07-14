open! Core
open Racing_map

(*_ The dune rule copies maps/castle_run.sexp next to the test binary. *)
let castle_run = lazy (Game_map.load_file_exn "castle_run.sexp")

let%expect_test "castle-run loads, validates, and summarizes" =
  let map = force castle_run in
  let features =
    Game_map.initial_features map
    |> List.map ~f:(fun (feature : Feature.t) ->
      ( Feature_id.to_int feature.id
      , Feature.kind feature
      , List.length feature.cells ))
    |> List.sort ~compare:[%compare: int * Feature.Kind.t * int]
  in
  print_s
    [%sexp
      { name = (Game_map.name map : string)
      ; laps_to_win = (Game_map.laps_to_win map : int)
      ; cols = (Game_map.cols map : int)
      ; rows = (Game_map.rows map : int)
      ; checkpoints = (Array.length (Game_map.checkpoints map) : int)
      ; start_slots = (List.length (Game_map.start_grid map) : int)
      ; features_by_id_kind_cells =
          (features : (int * Feature.Kind.t * int) list)
      }];
  [%expect
    {|
    ((name castle-run) (laps_to_win 3) (cols 26) (rows 15) (checkpoints 4)
     (start_slots 4)
     (features_by_id_kind_cells ((0 Bridge 4) (1 Gate 2) (2 Stalactite 2))))
    |}]
;;

let%expect_test "terrain, environment, and checkpoint queries" =
  let map = force castle_run in
  let surface cell = Game_map.base_surface_at map cell in
  print_s
    [%sexp
      { cave_road = (surface { col = 10; row = 2 } : Surface.t)
      ; interior_wall = (surface { col = 10; row = 7 } : Surface.t)
      ; forest_border = (surface { col = 0; row = 0 } : Surface.t)
      ; out_of_bounds_reads_wall =
          ((surface { col = -1; row = -1 }, surface { col = 26; row = 15 })
           : Surface.t * Surface.t)
      }];
  [%expect
    {|
    ((cave_road Road) (interior_wall Wall) (forest_border Trees)
     (out_of_bounds_reads_wall (Wall Wall)))
    |}];
  let environment cell = Game_map.environment_at map cell in
  print_s
    [%sexp
      { stalactite_cell = (environment { col = 14; row = 2 } : Environment.t)
      ; outer_left_lane = (environment { col = 2; row = 5 } : Environment.t)
      ; top_corridor = (environment { col = 20; row = 12 } : Environment.t)
      }];
  [%expect
    {| ((stalactite_cell Cave) (outer_left_lane Forest) (top_corridor Castle)) |}];
  print_s
    [%sexp
      { start_line =
          (Game_map.checkpoint_at map { col = 23; row = 7 } : int option)
      ; open_road =
          (Game_map.checkpoint_at map { col = 10; row = 2 } : int option)
      }];
  [%expect {| ((start_line (0)) (open_road ())) |}]
;;

let try_load text =
  match Game_map.load (Sexp.of_string text) with
  | Ok (_ : Game_map.t) -> print_endline "unexpectedly loaded"
  | Error error -> print_s [%sexp (error : Error.t)]
;;

let%expect_test "a broken map is rejected" =
  (* Only one checkpoint (need >= 2); shape errors are reported before the
     semantic checks (its cell sitting on Wall) get a chance to run. *)
  try_load
    {|((name bad)
       (laps_to_win 1)
       (cell_size 1.0)
       (surfaces ((Wall Wall Wall) (Wall Road Wall) (Wall Wall Wall)))
       (environments
        ((Castle Castle Castle) (Castle Castle Castle) (Castle Castle Castle)))
       (checkpoints
        (((index 0)
          (cells (((col 0) (row 0))))
          (respawn ((pos ((x 1.5) (y 1.5))) (heading 0))))))
       (start_grid (((pos ((x 1.5) (y 1.5))) (heading 0))))
       (features ()))|};
  [%expect {| ("map needs at least two checkpoints" (checkpoint_count 1)) |}]
;;

let%expect_test "ragged grids are rejected" =
  try_load
    {|((name ragged)
       (laps_to_win 1)
       (cell_size 1.0)
       (surfaces ((Road Road) (Road)))
       (environments ((Castle Castle) (Castle Castle)))
       (checkpoints ())
       (start_grid ())
       (features ()))|};
  [%expect
    {|
    ("start_grid must be nonempty"
     ("grid rows must all have the same nonzero length" (grid_name surfaces)
      (row_from_top 1) (row_length 1) (expected_cols 2))
     ("map needs at least two checkpoints" (checkpoint_count 0)))
    |}]
;;

let%expect_test "ice patches cannot be authored into a map file" =
  (* The reachability errors below are expected too: validation blocks EVERY
     authored footprint at once, so the illegal ice patch also splits the
     one-lane corridor. *)
  try_load
    {|((name iced)
       (laps_to_win 1)
       (cell_size 1.0)
       (surfaces
        ((Wall Wall Wall Wall Wall) (Wall Road Road Road Wall) (Wall Wall Wall Wall Wall)))
       (environments
        ((Cave Cave Cave Cave Cave) (Cave Cave Cave Cave Cave) (Cave Cave Cave Cave Cave)))
       (checkpoints
        (((index 0)
          (cells (((col 1) (row 1))))
          (respawn ((pos ((x 1.5) (y 1.5))) (heading 0))))
         ((index 1)
          (cells (((col 3) (row 1))))
          (respawn ((pos ((x 3.5) (y 1.5))) (heading 0))))))
       (start_grid (((pos ((x 2.5) (y 1.5))) (heading 0))))
       (features (((kind Ice_patch) (cells (((col 2) (row 1))))))))|};
  [%expect
    {|
    (("ice patches cannot be authored; they are spawned in play"
      (feature_index 0))
     ("checkpoint is unreachable from the previous checkpoint with every feature blocking"
      (from_index 1) (to_index 0))
     ("checkpoint is unreachable from the previous checkpoint with every feature blocking"
      (from_index 0) (to_index 1))
     ("checkpoint 1 is unreachable from start slot with every feature blocking"
      (slot 0) (cell ((col 2) (row 1)))))
    |}]
;;
