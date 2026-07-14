open! Core
open Racing_types
open Racing_map

let castle_run = lazy (Game_map.load_file_exn "castle_run.sexp")

let id_of_kind state kind =
  Map_state.features state
  |> List.find_map_exn ~f:(fun (feature : Feature.t) ->
    match Feature.Kind.equal (Feature.kind feature) kind with
    | true -> Some feature.id
    | false -> None)
;;

let show_error = function
  | Ok (_ : Map_state.t * Map_state.Update.t list) ->
    print_endline "unexpectedly ok"
  | Error error -> print_s [%sexp (error : Error.t)]
;;

let%expect_test "bridge: telegraph, gap, auto-rebuild" =
  let map = force castle_run in
  let state = Map_state.create map in
  let bridge = id_of_kind state Feature.Kind.Bridge in
  let deck = { Cell.col = 12; row = 12 } in
  let state, updates =
    Map_state.apply_action
      state
      ~map
      ~action:(Track_action.Collapse_bridge bridge)
      ~now:Tick.zero
    |> ok_exn
  in
  print_s [%sexp (updates : Map_state.Update.t list)];
  [%expect
    {|
    ((Set
      ((id 0)
       (cells
        (((col 12) (row 12)) ((col 13) (row 12)) ((col 12) (row 13))
         ((col 13) (row 13))))
       (payload (Bridge ((phase (Collapsing (falls_at 30)))))))))
    |}];
  (* the telegraph is a warning, not a hole yet *)
  print_s [%sexp (Map_state.is_gap state ~map deck : bool)];
  [%expect {| false |}];
  (* sabotaging a bridge that is already falling is rejected *)
  show_error
    (Map_state.apply_action
       state
       ~map
       ~action:(Track_action.Collapse_bridge bridge)
       ~now:Tick.zero);
  [%expect
    {| ("bridge is not intact" (id 0) (phase (Collapsing (falls_at 30)))) |}];
  (* the deck falls: a gap opens, but the base surface under it is still road *)
  let state, updates = Map_state.tick state ~now:(Tick.add Tick.zero 30) in
  print_s [%sexp (updates : Map_state.Update.t list)];
  [%expect
    {|
    ((Set
      ((id 0)
       (cells
        (((col 12) (row 12)) ((col 13) (row 12)) ((col 12) (row 13))
         ((col 13) (row 13))))
       (payload (Bridge ((phase (Collapsed (rebuilt_at 330)))))))))
    |}];
  print_s
    [%sexp
      { is_gap = (Map_state.is_gap state ~map deck : bool)
      ; surface_under =
          (Map_state.surface_at state ~map { Position.x = 12.5; y = 12.5 }
           : Surface.t)
      }];
  [%expect {| ((is_gap true) (surface_under Road)) |}];
  (* auto-rebuild keeps the lap completable *)
  let state, updates = Map_state.tick state ~now:(Tick.add Tick.zero 330) in
  print_s [%sexp (updates : Map_state.Update.t list)];
  [%expect
    {|
    ((Set
      ((id 0)
       (cells
        (((col 12) (row 12)) ((col 13) (row 12)) ((col 12) (row 13))
         ((col 13) (row 13))))
       (payload (Bridge ((phase Intact)))))))
    |}];
  print_s [%sexp (Map_state.is_gap state ~map deck : bool)];
  [%expect {| false |}]
;;

let%expect_test "gate: closes solid, then reopens" =
  let map = force castle_run in
  let state = Map_state.create map in
  let gate = id_of_kind state Feature.Kind.Gate in
  let cell = { Cell.col = 5; row = 7 } in
  let state, (_ : Map_state.Update.t list) =
    Map_state.apply_action
      state
      ~map
      ~action:(Track_action.Close_gate gate)
      ~now:Tick.zero
    |> ok_exn
  in
  (* still passable while the portcullis descends *)
  print_s [%sexp (Map_state.is_blocked state ~map cell : bool)];
  [%expect {| false |}];
  let state, (_ : Map_state.Update.t list) =
    Map_state.tick state ~now:(Tick.add Tick.zero 45)
  in
  print_s
    [%sexp
      { is_blocked = (Map_state.is_blocked state ~map cell : bool)
      ; composed_surface =
          (Map_state.surface_at state ~map { Position.x = 5.5; y = 7.5 }
           : Surface.t)
      ; near_the_gate =
          (Map_state.features_near
             state
             ~map
             ~center:{ Position.x = 5.5; y = 9.5 }
             ~radius:3.
           |> List.map ~f:Feature.kind
           : Feature.Kind.t list)
      }];
  [%expect
    {| ((is_blocked true) (composed_surface Wall) (near_the_gate (Gate))) |}];
  let state, updates = Map_state.tick state ~now:(Tick.add Tick.zero 285) in
  print_s [%sexp (updates : Map_state.Update.t list)];
  [%expect
    {|
    ((Set
      ((id 1) (cells (((col 5) (row 7)) ((col 6) (row 7))))
       (payload (Gate ((phase Open)))))))
    |}];
  print_s [%sexp (Map_state.is_blocked state ~map cell : bool)];
  [%expect {| false |}]
;;

let%expect_test "ice: placed on open road, slows, melted by flame magic" =
  let map = force castle_run in
  let state = Map_state.create map in
  let center = { Position.x = 10.5; y = 2.5 } in
  let state, updates =
    Map_state.apply_action
      state
      ~map
      ~action:(Track_action.Place_ice center)
      ~now:Tick.zero
    |> ok_exn
  in
  print_s [%sexp (updates : Map_state.Update.t list)];
  [%expect
    {|
    ((Set
      ((id 3)
       (cells
        (((col 9) (row 1)) ((col 10) (row 1)) ((col 11) (row 1))
         ((col 9) (row 2)) ((col 10) (row 2)) ((col 11) (row 2))
         ((col 9) (row 3)) ((col 10) (row 3)) ((col 11) (row 3))))
       (payload (Ice_patch ((melts_at 240)))))))
    |}];
  print_s [%sexp (Map_state.traction_at state ~map center : float)];
  [%expect {| 0.3 |}];
  (* ice cannot be poured onto the castle's interior wall *)
  show_error
    (Map_state.apply_action
       state
       ~map
       ~action:(Track_action.Place_ice { Position.x = 10.5; y = 7.5 })
       ~now:Tick.zero);
  [%expect
    {|
    ("ice must land on open road" (center ((x 10.5) (y 7.5)))
     (not_open_road
      (((col 9) (row 6)) ((col 10) (row 6)) ((col 11) (row 6)) ((col 9) (row 7))
       ((col 10) (row 7)) ((col 11) (row 7)) ((col 9) (row 8)) ((col 10) (row 8))
       ((col 11) (row 8)))))
    |}];
  (* a driver's flame magic melts it early *)
  let ice =
    match updates with
    | [ Set (feature : Feature.t) ] -> feature.id
    | []
    | [ Removed (_ : Feature_id.t) ]
    | _ :: _ :: (_ : Map_state.Update.t list) ->
      failwith "expected exactly one Set update from Place_ice"
  in
  let state, updates = Map_state.melt_ice state ~id:ice |> ok_exn in
  print_s [%sexp (updates : Map_state.Update.t list)];
  [%expect {| ((Removed 3)) |}];
  print_s [%sexp (Map_state.traction_at state ~map center : float)];
  [%expect {| 1 |}];
  (* flame magic only counters ice *)
  show_error
    (Map_state.melt_ice state ~id:(id_of_kind state Feature.Kind.Gate));
  [%expect
    {| ("feature is not an ice patch" (id 1) ("Feature.kind feature" Gate)) |}]
;;

let%expect_test "every update replays into an identical state" =
  let map = force castle_run in
  let initial = Map_state.create map in
  let bridge = id_of_kind initial Feature.Kind.Bridge in
  let gate = id_of_kind initial Feature.Kind.Gate in
  let final, updates =
    let state = initial in
    let state, u1 =
      Map_state.apply_action
        state
        ~map
        ~action:(Track_action.Collapse_bridge bridge)
        ~now:Tick.zero
      |> ok_exn
    in
    let state, u2 =
      Map_state.apply_action
        state
        ~map
        ~action:(Track_action.Close_gate gate)
        ~now:(Tick.add Tick.zero 5)
      |> ok_exn
    in
    let state, u3 =
      Map_state.apply_action
        state
        ~map
        ~action:(Track_action.Place_ice { Position.x = 10.5; y = 2.5 })
        ~now:(Tick.add Tick.zero 10)
      |> ok_exn
    in
    let state, u4 = Map_state.tick state ~now:(Tick.add Tick.zero 50) in
    let state, u5 = Map_state.tick state ~now:(Tick.add Tick.zero 400) in
    state, List.concat [ u1; u2; u3; u4; u5 ]
  in
  let replica =
    List.fold updates ~init:initial ~f:(fun replica update ->
      Map_state.apply_update replica update)
  in
  print_s [%sexp (Map_state.equal replica final : bool)];
  [%expect {| true |}]
;;

let%expect_test "driver viewport composes the gate; caves are dark" =
  let map = force castle_run in
  let state = Map_state.create map in
  let center = { Position.x = 5.5; y = 7.5 } in
  let show state =
    let viewport =
      Map_state.viewport state ~map ~center ~half_extent_cells:2
    in
    print_s
      [%sexp
        { origin = (viewport.origin : Cell.t)
        ; is_dark = (viewport.is_dark : bool)
        ; features =
            (List.map viewport.features ~f:Feature.kind
             : Feature.Kind.t list)
        ; surfaces = (viewport.surfaces : Surface.t array array)
        }]
  in
  show state;
  [%expect
    {|
    ((origin ((col 3) (row 5))) (is_dark false) (features (Gate))
     (surfaces
      ((Trees Trees Road Road Wall) (Trees Trees Road Road Wall)
       (Trees Trees Road Road Wall) (Trees Trees Road Road Wall)
       (Trees Trees Road Road Wall))))
    |}];
  let gate = id_of_kind state Feature.Kind.Gate in
  let state, (_ : Map_state.Update.t list) =
    Map_state.apply_action
      state
      ~map
      ~action:(Track_action.Close_gate gate)
      ~now:Tick.zero
    |> ok_exn
  in
  let state, (_ : Map_state.Update.t list) =
    Map_state.tick state ~now:(Tick.add Tick.zero 45)
  in
  show state;
  [%expect
    {|
    ((origin ((col 3) (row 5))) (is_dark false) (features (Gate))
     (surfaces
      ((Trees Trees Road Road Wall) (Trees Trees Road Road Wall)
       (Trees Trees Wall Wall Wall) (Trees Trees Road Road Wall)
       (Trees Trees Road Road Wall))))
    |}];
  let cave =
    Map_state.viewport
      state
      ~map
      ~center:{ Position.x = 14.5; y = 2.5 }
      ~half_extent_cells:1
  in
  print_s
    [%sexp
      { is_dark = (cave.is_dark : bool)
      ; features =
          (List.map cave.features ~f:Feature.kind : Feature.Kind.t list)
      }];
  [%expect {| ((is_dark true) (features (Stalactite))) |}]
;;

let%expect_test "drift guards: every kind, surface, and environment" =
  print_s [%sexp (Feature.Kind.all : Feature.Kind.t list)];
  [%expect {| (Bridge Gate Stalactite Ice_patch) |}];
  print_s [%sexp (Surface.all : Surface.t list)];
  [%expect {| (Road Wall Trees) |}];
  print_s [%sexp (Environment.all : Environment.t list)];
  [%expect {| (Forest Castle Cave) |}]
;;
