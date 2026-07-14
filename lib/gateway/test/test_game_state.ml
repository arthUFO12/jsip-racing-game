open! Core
open Racing_types
open Racing_map
open Racing_gateway

(* A purpose-built track so every expected number below is checkable by hand
   (castle_run.sexp is gameplay-tuned and free to change). The ring: *)
(* row 6 W W W W W W W W W *)
(* row 5 W R R R R R R R W <- top lane; cars spawn at (1,5) *)
(* row 4 W R W W W R R R W *)
(* row 3 W R W W W R R R W <- cols 5-7 x rows 2-4: a 3x3 road *)
(* row 2 W R W W W R R R W plaza, room for an ice patch's *)
(* row 1 W R R R R R R R W 1.5-unit footprint *)
(* row 0 W W W W W W W W W *)
(* Checkpoint 0 sits at (4,1), checkpoint 1 at (4,5) — reachable both ways
   around the ring, so [Game_map.load]'s worst-case-sabotage check passes.
   Columns 0-1 are Forest (vines are legal there), the rest Castle. Start
   slots: (1.5, 5.5) facing east in forest, (5.5, 1.5) in castle. *)
let map_sexp ~features =
  Sexp.of_string
    [%string
      {|
((name test-ring)
 (laps_to_win 2)
 (cell_size 1.0)
 (surfaces
  ((Wall Wall Wall Wall Wall Wall Wall Wall Wall)
   (Wall Road Road Road Road Road Road Road Wall)
   (Wall Road Wall Wall Wall Road Road Road Wall)
   (Wall Road Wall Wall Wall Road Road Road Wall)
   (Wall Road Wall Wall Wall Road Road Road Wall)
   (Wall Road Road Road Road Road Road Road Wall)
   (Wall Wall Wall Wall Wall Wall Wall Wall Wall)))
 (environments
  ((Forest Forest Castle Castle Castle Castle Castle Castle Castle)
   (Forest Forest Castle Castle Castle Castle Castle Castle Castle)
   (Forest Forest Castle Castle Castle Castle Castle Castle Castle)
   (Forest Forest Castle Castle Castle Castle Castle Castle Castle)
   (Forest Forest Castle Castle Castle Castle Castle Castle Castle)
   (Forest Forest Castle Castle Castle Castle Castle Castle Castle)
   (Forest Forest Castle Castle Castle Castle Castle Castle Castle)))
 (checkpoints
  (((index 0)
    (cells (((col 4) (row 1))))
    (respawn ((pos ((x 4.5) (y 1.5))) (heading 0))))
   ((index 1)
    (cells (((col 4) (row 5))))
    (respawn ((pos ((x 4.5) (y 5.5))) (heading 0))))))
 (start_grid
  (((pos ((x 1.5) (y 5.5))) (heading 0))
   ((pos ((x 5.5) (y 1.5))) (heading 0))))
 (features %{features}))
|}]
;;

let test_map = lazy (ok_exn (Game_map.load (map_sexp ~features:"()")))

(* The same ring plus one authored bridge at (3,5) — on the top lane between
   Alice's start and checkpoint 1. Load validation still passes: with the
   bridge collapsed, the lap survives the long way around. *)
let bridge_map =
  lazy
    (ok_exn
       (Game_map.load
          (map_sexp
             ~features:"(((kind Bridge) (cells (((col 3) (row 5))))))")))
;;

let create () = Game_state.create ~map:(force test_map)

let join t ~name ~team ~role =
  Game_state.join t { name; team = Team_id.of_int team; role }
;;

let join_exn t ~name ~team ~role = ok_exn (join t ~name ~team ~role)

(* Alice drives for team 1 (forest side), Bob works its track; Carol drives
   for team 2 (castle side), Dan works its track. *)
let full_lobby ?(map = test_map) () =
  let t = Game_state.create ~map:(force map) in
  let alice = join_exn t ~name:"Alice" ~team:1 ~role:Driver in
  let bob = join_exn t ~name:"Bob" ~team:1 ~role:Track_player in
  let carol = join_exn t ~name:"Carol" ~team:2 ~role:Driver in
  let dan = join_exn t ~name:"Dan" ~team:2 ~role:Track_player in
  t, alice, bob, carol, dan
;;

let steps t n =
  for _ = 1 to n do
    Game_state.step t
  done
;;

(* countdown_seconds (3) * ticks_per_second (30). *)
let to_green t = steps t 90
let accelerate = { Driver_input.idle with accelerate = true }

let show_result = function
  | Ok () -> print_endline "Ok"
  | Error error -> printf !"Error: %{Error#hum}\n" error
;;

let show_status t =
  printf !"%{sexp: Race_status.t}\n" (Game_state.snapshot t).race_status
;;

let show_car t player_id =
  let snapshot = Game_state.snapshot t in
  let { Rpc_protocol.Car.position; velocity; progress } =
    Map.find_exn snapshot.cars player_id
  in
  printf
    "(%.2f, %.2f) at %.2f u/s, hunting checkpoint %d, laps %d\n"
    position.x
    position.y
    (Speed.to_float velocity.speed)
    progress.next_index
    progress.laps_completed
;;

let show_effects t player_id =
  let snapshot = Game_state.snapshot t in
  match Map.find_exn snapshot.effects player_id with
  | [] -> print_endline "no effects"
  | effects ->
    List.iter effects ~f:(fun { Effect.kind; remaining } ->
      printf
        !"%{sexp: Effect.Kind.t} for %.2fs\n"
        kind
        (Time_ns.Span.to_sec remaining))
;;

let show_inventory t player_id =
  let snapshot = Game_state.snapshot t in
  printf
    !"%{sexp: Powerup.t list}\n"
    (Map.find_exn snapshot.inventories player_id)
;;

let show_track_features t =
  let snapshot = Game_state.snapshot t in
  match Map_state.features snapshot.track with
  | [] -> print_endline "no live features"
  | features ->
    List.iter features ~f:(fun feature ->
      printf !"%{sexp: Feature.Kind.t}\n" (Feature.kind feature))
;;

let%expect_test "join fills seats, spawns cars, stocks stock, forms teams" =
  let t, _alice, _bob, _carol, _dan = full_lobby () in
  let snapshot = Game_state.snapshot t in
  List.iter snapshot.players ~f:(fun { player; team; role } ->
    printf
      !"%s: team %d, %{sexp: Role.t}\n"
      (Player_name.to_string player.name)
      (Team_id.to_int team)
      role);
  [%expect
    {|
    Alice: team 1, Driver
    Bob: team 1, Track_player
    Carol: team 2, Driver
    Dan: team 2, Track_player
    |}];
  List.iter snapshot.teams ~f:(fun (team : Team.t) ->
    printf
      "team %d: %s drives, %s works the track\n"
      (Team_id.to_int team.id)
      (Player_name.to_string team.driver.name)
      (Player_name.to_string team.track_player.name));
  [%expect
    {|
    team 1: Alice drives, Bob works the track
    team 2: Carol drives, Dan works the track
    |}];
  Map.iteri snapshot.cars ~f:(fun ~key ~data:{ position; _ } ->
    printf
      "player %d starts at (%.1f, %.1f)\n"
      (Player_id.to_int key)
      position.x
      position.y);
  [%expect
    {|
    player 0 starts at (1.5, 5.5)
    player 2 starts at (5.5, 1.5)
    |}];
  Map.iteri snapshot.inventories ~f:(fun ~key ~data ->
    printf
      !"player %d holds %{sexp: Powerup.t list}\n"
      (Player_id.to_int key)
      data);
  [%expect
    {|
    player 0 holds ()
    player 1 holds (Speed_boost Invincibility Glider Flame_magic Flashlight Axe)
    player 2 holds ()
    player 3 holds (Speed_boost Invincibility Glider Flame_magic Flashlight Axe)
    |}]
;;

let%expect_test "join errors: bad names, taken seats, a full start grid" =
  let t = create () in
  let show = function
    | Ok id -> printf "Ok, player %d\n" (Player_id.to_int id)
    | Error error -> printf !"Error: %{Error#hum}\n" error
  in
  show (join t ~name:"not ok!" ~team:1 ~role:Driver);
  [%expect
    {|
    Error: ("player name may only contain letters, digits, '_' and '-'"
     (name "not ok!"))
    |}];
  show (join t ~name:"Alice" ~team:1 ~role:Driver);
  [%expect {| Ok, player 0 |}];
  show (join t ~name:"Eve" ~team:1 ~role:Driver);
  [%expect {| Error: ("seat is already taken" (team 1) (role Driver)) |}];
  show (join t ~name:"Carol" ~team:2 ~role:Driver);
  [%expect {| Ok, player 1 |}];
  (* The test ring has two start slots, both now occupied. *)
  show (join t ~name:"Frank" ~team:3 ~role:Driver);
  [%expect {| Error: ("no start slots left on this map" (start_slots 2)) |}]
;;

let%expect_test "the countdown starts with the first complete team" =
  let t = create () in
  let (_ : Player_id.t) = join_exn t ~name:"Alice" ~team:1 ~role:Driver in
  let (_ : Player_id.t) = join_exn t ~name:"Carol" ~team:2 ~role:Driver in
  (* Two lone drivers are not a team: no amount of waiting starts this race. *)
  steps t 200;
  show_status t;
  [%expect {| Countdown |}];
  let (_ : Player_id.t) =
    join_exn t ~name:"Bob" ~team:1 ~role:Track_player
  in
  steps t 89;
  show_status t;
  [%expect {| Countdown |}];
  steps t 1;
  show_status t;
  [%expect {| Racing |}]
;;

let%expect_test "the powerup economy: stock, assist, spend" =
  let t, alice, bob, _carol, dan = full_lobby () in
  (* Assists are legal during the countdown — stocking your driver up before
     the green light is part of the game... *)
  show_result (Game_state.assist_teammate t bob Speed_boost);
  [%expect {| Ok |}];
  show_inventory t alice;
  [%expect {| (Speed_boost) |}];
  show_inventory t bob;
  [%expect {| (Invincibility Glider Flame_magic Flashlight Axe) |}];
  (* ...but spending waits for the race. *)
  show_result (Game_state.use_powerup t alice Speed_boost);
  [%expect {| Error: the race has not started yet |}];
  show_result (Game_state.assist_teammate t bob Speed_boost);
  [%expect
    {|
    Error: ("powerup is not in your inventory" (powerup Speed_boost)
     (inventory (Invincibility Glider Flame_magic Flashlight Axe)))
    |}];
  show_result (Game_state.assist_teammate t alice Glider);
  [%expect
    {| Error: only track players hold stock to grant; drivers use what they are given |}];
  to_green t;
  show_result (Game_state.use_powerup t alice Glider);
  [%expect
    {|
    Error: ("powerup is not in your inventory" (powerup Glider)
     (inventory (Speed_boost)))
    |}];
  show_result (Game_state.use_powerup t dan Speed_boost);
  [%expect
    {| Error: track players grant powerups to their driver (assist_teammate) rather than using them |}];
  show_result (Game_state.use_powerup t alice Speed_boost);
  [%expect {| Ok |}];
  show_effects t alice;
  [%expect {| (Powerup Speed_boost) for 4.00s |}];
  show_inventory t alice;
  [%expect {| () |}]
;;

let%expect_test "who may sabotage whom" =
  let t, alice, bob, carol, dan = full_lobby () in
  show_result (Game_state.use_interference t dan (Car (Vines alice)));
  [%expect {| Error: the race has not started yet |}];
  to_green t;
  show_result (Game_state.use_interference t alice (Car (Vines carol)));
  [%expect {| Error: only track players can sabotage |}];
  show_result (Game_state.use_interference t dan (Car (Vines carol)));
  [%expect {| Error: cannot sabotage your own driver |}];
  show_result (Game_state.use_interference t dan (Car (Vines bob)));
  [%expect
    {| Error: ("target is a track player, not a driver" (victim 1)) |}];
  (* Carol spawns on the castle side; vines are a forest power. *)
  show_result (Game_state.use_interference t bob (Car (Vines carol)));
  [%expect
    {| Error: ("vines only grow in the forest" (environment Castle)) |}];
  show_result (Game_state.use_interference t bob (Car (Mud_bomb carol)));
  [%expect {| Ok |}];
  show_effects t carol;
  [%expect {| Mud_bomb for 3.00s |}];
  show_result (Game_state.use_interference t dan (Car Slick_track));
  [%expect
    {| Error: Slick_track is superseded: send Track (Place_ice _) instead |}]
;;

let%expect_test "invincibility bounces powerdowns until it runs out" =
  let t, alice, bob, _carol, dan = full_lobby () in
  show_result (Game_state.assist_teammate t bob Invincibility);
  [%expect {| Ok |}];
  to_green t;
  show_result (Game_state.use_powerup t alice Invincibility);
  [%expect {| Ok |}];
  (* The vines are cast legally and answer [Ok] — they just bounce. *)
  show_result (Game_state.use_interference t dan (Car (Vines alice)));
  [%expect {| Ok |}];
  show_effects t alice;
  [%expect {| (Powerup Invincibility) for 5.00s |}];
  (* 5 seconds = 150 ticks later the shield is gone... *)
  steps t 150;
  show_effects t alice;
  [%expect {| no effects |}];
  show_result (Game_state.use_interference t dan (Car (Vines alice)));
  [%expect {| Ok |}];
  show_effects t alice;
  [%expect {| Vines for 4.00s |}]
;;

let%expect_test "vines wear off on their own, or an axe cuts them early" =
  let t, alice, bob, _carol, dan = full_lobby () in
  to_green t;
  show_result (Game_state.use_interference t dan (Car (Vines alice)));
  [%expect {| Ok |}];
  show_effects t alice;
  [%expect {| Vines for 4.00s |}];
  steps t 119;
  show_effects t alice;
  [%expect {| Vines for 0.03s |}];
  steps t 1;
  show_effects t alice;
  [%expect {| no effects |}];
  (* Round two: this time Alice cuts free immediately. *)
  show_result (Game_state.use_interference t dan (Car (Vines alice)));
  [%expect {| Ok |}];
  show_result (Game_state.assist_teammate t bob Axe);
  [%expect {| Ok |}];
  show_result (Game_state.use_powerup t alice Axe);
  [%expect {| Ok |}];
  show_effects t alice;
  [%expect {| no effects |}];
  show_inventory t alice;
  [%expect {| () |}]
;;

let%expect_test "track sabotage flows through the map, and flame counters it"
  =
  let t, alice, bob, _carol, dan = full_lobby () in
  to_green t;
  (* The test ring authors no features, so there is no gate 99 to close —
     [Map_state.apply_action] rejects it, and the server just relays. *)
  show_result
    (Game_state.use_interference
       t
       dan
       (Track (Close_gate (Feature_id.of_int 99))));
  [%expect {| Error: ("no such feature" (id 99)) |}];
  (* Ice in the middle of the plaza: a fresh feature, and the ground under it
     turns slick (ice_traction in lib/map/feature.ml). *)
  show_result
    (Game_state.use_interference
       t
       dan
       (Track (Place_ice { x = 6.5; y = 3.5 })));
  [%expect {| Ok |}];
  show_track_features t;
  [%expect {| Ice_patch |}];
  let show_traction () =
    let snapshot = Game_state.snapshot t in
    printf
      "traction at the plaza center: %.2f\n"
      (Map_state.traction_at
         snapshot.track
         ~map:(Game_state.game_map t)
         { x = 6.5; y = 3.5 })
  in
  show_traction ();
  [%expect {| traction at the plaza center: 0.30 |}];
  (* Flame magic only works within reach — and a miss does not burn the
     charge. *)
  show_result (Game_state.assist_teammate t bob Flame_magic);
  [%expect {| Ok |}];
  show_result (Game_state.use_powerup t alice Flame_magic);
  [%expect {| Error: no ice within reach to melt |}];
  show_inventory t alice;
  [%expect {| (Flame_magic) |}];
  (* Drive east along the top lane until the plaza is in reach. *)
  Game_state.set_driver_input t alice accelerate;
  steps t 30;
  Game_state.set_driver_input t alice Driver_input.idle;
  show_result (Game_state.use_powerup t alice Flame_magic);
  [%expect {| Ok |}];
  show_track_features t;
  [%expect {| no live features |}];
  show_traction ();
  [%expect {| traction at the plaza center: 1.00 |}]
;;

let%expect_test "driving: locked at the line, then east until the wall" =
  let t, alice, _bob, _carol, _dan = full_lobby () in
  (* Held keys are remembered even before the green light... *)
  Game_state.set_driver_input t alice accelerate;
  steps t 89;
  show_status t;
  show_car t alice;
  [%expect
    {|
    Countdown
    (1.50, 5.50) at 0.00 u/s, hunting checkpoint 1, laps 0
    |}];
  (* ...and the car only moves once the race is on. One racing tick: 8
     u/s^2 * (1/30)s. *)
  steps t 1;
  show_status t;
  show_car t alice;
  [%expect
    {|
    Racing
    (1.51, 5.50) at 0.27 u/s, hunting checkpoint 1, laps 0
    |}];
  (* After a second at full throttle Alice has crossed checkpoint 1 at (4,5)
     and is hunting the start/finish line. *)
  steps t 29;
  show_car t alice;
  [%expect {| (5.63, 5.50) at 8.00 u/s, hunting checkpoint 0, laps 0 |}];
  (* The lane dead-ends into the wall at x = 8: bonk, not tunnel. *)
  steps t 8;
  show_car t alice;
  [%expect {| (7.75, 5.50) at 0.00 u/s, hunting checkpoint 0, laps 0 |}]
;;

(* The bridge run shared by the falling and gliding tests: at the green light
   Dan collapses the bridge at (3,5) on Alice's lane, and we wait out the
   30-tick telegraph (bridge_telegraph_ticks in lib/map/map_state.ml) until
   its cells become a real gap. Alice idles at the start line the whole time,
   so both tests then drive the same trajectory: 18 accelerating ticks put
   her car at x = 3.02, inside the gap cell. *)
let race_to_an_open_gap () =
  let t, alice, bob, _carol, dan = full_lobby ~map:bridge_map () in
  to_green t;
  show_result
    (Game_state.use_interference
       t
       dan
       (Track (Collapse_bridge (Feature_id.of_int 0))));
  let show_gap () =
    let snapshot = Game_state.snapshot t in
    printf
      "gap at (3,5): %b\n"
      (Map_state.is_gap
         snapshot.track
         ~map:(Game_state.game_map t)
         { Cell.col = 3; row = 5 })
  in
  (* Telegraph first — the co-pilot's warning window, still drivable. *)
  show_gap ();
  steps t 30;
  show_gap ();
  t, alice, bob
;;

let%expect_test "falling: the gap drops Alice back to her last checkpoint" =
  let t, alice, _bob = race_to_an_open_gap () in
  [%expect {|
    Ok
    gap at (3,5): false
    gap at (3,5): true
    |}];
  Game_state.set_driver_input t alice accelerate;
  steps t 18;
  (* She has not touched checkpoint 1 yet, so "last touched" wraps to the
     start/finish line — checkpoint 0's respawn at (4.5, 1.5), speed zero. *)
  show_car t alice;
  [%expect {| (4.50, 1.50) at 0.00 u/s, hunting checkpoint 1, laps 0 |}]
;;

let%expect_test "gliding: the same gap, sailed over" =
  let t, alice, bob = race_to_an_open_gap () in
  [%expect {|
    Ok
    gap at (3,5): false
    gap at (3,5): true
    |}];
  show_result (Game_state.assist_teammate t bob Glider);
  show_result (Game_state.use_powerup t alice Glider);
  [%expect {|
    Ok
    Ok
    |}];
  Game_state.set_driver_input t alice accelerate;
  (* Same 18 ticks as the falling test: this time she is ON the gap cell,
     aloft, still moving... *)
  steps t 18;
  show_car t alice;
  [%expect {| (3.02, 5.50) at 4.80 u/s, hunting checkpoint 1, laps 0 |}];
  (* ...and six ticks later she has crossed it and banked checkpoint 1. *)
  steps t 6;
  show_car t alice;
  [%expect {| (4.17, 5.50) at 6.40 u/s, hunting checkpoint 0, laps 0 |}]
;;
