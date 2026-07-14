open! Core
open Racing_map

(*_ The dune rule copies maps/castle_run.sexp next to the test binary. *)
let castle_run = lazy (Game_map.load_file_exn "castle_run.sexp")

let%expect_test "castle-run loads, validates, and summarizes" =
  let map = force castle_run in
  let features =
    Game_map.initial_features map
    |> List.map ~f:(fun (feature : Feature.t) ->
      Feature_id.to_int feature.id, Feature.kind feature, List.length feature.cells)
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
      ; features_by_id_kind_cells = (features : (int * Feature.Kind.t * int) list)
      }];
  [%expect {| |}]
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
  [%expect {| |}];
  let environment cell = Game_map.environment_at map cell in
  print_s
    [%sexp
      { stalactite_cell = (environment { col = 14; row = 2 } : Environment.t)
      ; outer_left_lane = (environment { col = 2; row = 5 } : Environment.t)
      ; top_corridor = (environment { col = 20; row = 12 } : Environment.t)
      }];
  [%expect {| |}];
  print_s
    [%sexp
      { start_line = (Game_map.checkpoint_at map { col = 23; row = 7 } : int option)
      ; open_road = (Game_map.checkpoint_at map { col = 10; row = 2 } : int option)
      }];
  [%expect {| |}]
;;

let try_load text =
  match Game_map.load (Sexp.of_string text) with
  | Ok (_ : Game_map.t) -> print_endline "unexpectedly loaded"
  | Error error -> print_s [%sexp (error : Error.t)]
;;

let%expect_test "a broken map is rejected with every error, not just the first" =
  (* Only one checkpoint (need >= 2), and its cells sit on Wall. *)
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
  [%expect {| |}]
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
  [%expect {| |}]
;;

let%expect_test "ice patches cannot be authored into a map file" =
  (* Otherwise-valid corridor so the ice error is the only one. *)
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
  [%expect {| |}]
;;
