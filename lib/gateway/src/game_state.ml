open! Core
open Racing_types
open Racing_map

let ticks_per_second = 30
let tick_duration = Time_ns.Span.of_int_ns (1_000_000_000 / ticks_per_second)

let ticks_of_seconds seconds =
  Float.iround_nearest_exn (seconds *. Float.of_int ticks_per_second)
;;

let expiry ~now ~seconds = Tick.add now (ticks_of_seconds seconds)

(* Game-tuning constants — the spec's "X seconds", pinned to numbers in one
   place until a config module exists. *)
let countdown_seconds = 3.
let speed_boost_seconds = 4.
let invincibility_seconds = 5.
let glider_seconds = 6.
let flashlight_seconds = 10.
let vines_seconds = 4.
let mud_bomb_seconds = 3.

(* How far around the car flame magic reaches, in world units. *)
let flame_magic_radius = 1.5
let track_player_starting_stock : Powerup.t list = Powerup.all

module Race = struct
  (* The lifecycle knows more than the protocol's {!Race_status.t}: clients
     only need locked/racing/done, the server also needs when the green light
     is. *)
  type t =
    | Waiting (* no complete team yet *)
    | Countdown of { green_at : Tick.t }
    | Racing
    | Finished

  let to_status t : Race_status.t =
    match t with
    | Waiting | Countdown _ -> Countdown
    | Racing -> Racing
    | Finished -> Finished
  ;;
end

module Car_state = struct
  (* One driver's live state. [effects] pairs each active effect with the
     absolute tick it expires — timers are expiry ticks (tick.mli); the
     snapshot converts them to the protocol's remaining-time view. *)
  type t =
    { mutable position : Position.t
    ; mutable velocity : Velocity.t
    ; mutable progress : Checkpoint.Progress.t
    ; mutable input : Driver_input.t
    ; mutable effects : (Effect.Kind.t * Tick.t) list
    }

  let spawn (pose : Pose.t) =
    { position = pose.pos
    ; velocity =
        Velocity.stationary ~facing:(Heading.of_radians_exn pose.heading)
    ; progress = Checkpoint.Progress.initial
    ; input = Driver_input.idle
    ; effects = []
    }
  ;;

  let has_effect t kind =
    List.exists t.effects ~f:(fun (active, (_ : Tick.t)) ->
      Effect.Kind.equal active kind)
  ;;

  let stun t = t.velocity <- { t.velocity with speed = Speed.zero }
end

module Seat = struct
  (* One team's two chairs, filling up as players join; {!Team.t} is only
     built once both are occupied. *)
  type t =
    { mutable driver : Player.t option
    ; mutable track_player : Player.t option
    }

  let empty () = { driver = None; track_player = None }
end

module Membership = struct
  type t =
    { player : Player.t
    ; team : Team_id.t
    ; role : Role.t
    }
end

type t =
  { map : Game_map.t
  ; mutable track : Map_state.t
  ; mutable tick : Tick.t
  ; mutable race : Race.t
  ; mutable next_player_id : int
  ; mutable join_order_rev : Player_id.t list
  ; seats : Seat.t Team_id.Table.t
  ; teams : Team.t Team_id.Table.t
  ; memberships : Membership.t Player_id.Table.t
  ; cars : Car_state.t Player_id.Table.t
  ; inventories : Powerup.t list Player_id.Table.t
  }

let create ~map =
  { map
  ; track = Map_state.create map
  ; tick = Tick.zero
  ; race = Waiting
  ; next_player_id = 0
  ; join_order_rev = []
  ; seats = Team_id.Table.create ()
  ; teams = Team_id.Table.create ()
  ; memberships = Player_id.Table.create ()
  ; cars = Player_id.Table.create ()
  ; inventories = Player_id.Table.create ()
  }
;;

let game_map t = t.map

(* {2 Joining} *)

let join t ({ name; team; role } : Rpc_protocol.Join_request.t) =
  let open Or_error.Let_syntax in
  let%bind name = Player_name.of_string name in
  let seat = Hashtbl.find_or_add t.seats team ~default:Seat.empty in
  let%bind () =
    let seat_is_taken =
      match role with
      | Driver -> Option.is_some seat.driver
      | Track_player -> Option.is_some seat.track_player
    in
    if seat_is_taken
    then
      Or_error.error_s
        [%message "seat is already taken" (team : Team_id.t) (role : Role.t)]
    else Ok ()
  in
  let%bind () =
    match role with
    | Track_player -> Ok ()
    | Driver ->
      let start_slots = List.length (Game_map.start_grid t.map) in
      if Hashtbl.length t.cars < start_slots
      then Ok ()
      else
        Or_error.error_s
          [%message "no start slots left on this map" (start_slots : int)]
  in
  let player_id = Player_id.of_int t.next_player_id in
  t.next_player_id <- t.next_player_id + 1;
  let player : Player.t = { id = player_id; name } in
  (match role with
   | Driver ->
     (* [nth_exn] is safe: the start-grid check above just passed. *)
     let pose =
       List.nth_exn (Game_map.start_grid t.map) (Hashtbl.length t.cars)
     in
     seat.driver <- Some player;
     Hashtbl.set t.cars ~key:player_id ~data:(Car_state.spawn pose);
     Hashtbl.set t.inventories ~key:player_id ~data:[]
   | Track_player ->
     seat.track_player <- Some player;
     Hashtbl.set
       t.inventories
       ~key:player_id
       ~data:track_player_starting_stock);
  Hashtbl.set t.memberships ~key:player_id ~data:{ player; team; role };
  t.join_order_rev <- player_id :: t.join_order_rev;
  (match seat.driver, seat.track_player with
   | Some driver, Some track_player ->
     (* Distinct freshly-allocated ids, so [create] cannot fail — if it does,
        the id allocator is broken and crashing is right. *)
     let full_team = ok_exn (Team.create ~id:team ~driver ~track_player) in
     Hashtbl.set t.teams ~key:team ~data:full_team;
     (match t.race with
      | Waiting ->
        t.race
        <- Countdown
             { green_at = expiry ~now:t.tick ~seconds:countdown_seconds }
      | Countdown _ | Racing | Finished -> ())
   | Some _, None | None, Some _ | None, None -> ());
  Ok player_id
;;

(* {2 Command plumbing} *)

let membership t player_id =
  match Hashtbl.find t.memberships player_id with
  | Some membership -> Ok membership
  | None ->
    Or_error.error_s [%message "unknown player" (player_id : Player_id.t)]
;;

(* Every [Membership.role = Driver] has a car: [join] creates them together. *)
let car_exn t player_id = Hashtbl.find_exn t.cars player_id

let ensure_racing t =
  match t.race with
  | Racing -> Ok ()
  | Waiting | Countdown _ ->
    Or_error.error_string "the race has not started yet"
  | Finished -> Or_error.error_string "the race is over"
;;

(* Removes one instance — inventories are multisets, and holding two gliders
   had better survive using one. *)
let rec remove_first inventory powerup =
  match inventory with
  | [] -> None
  | held :: rest ->
    if Powerup.equal held powerup
    then Some rest
    else Option.map (remove_first rest powerup) ~f:(fun rest -> held :: rest)
;;

let take_from_inventory t player_id powerup =
  let inventory =
    Hashtbl.find t.inventories player_id |> Option.value ~default:[]
  in
  match remove_first inventory powerup with
  | Some rest ->
    Hashtbl.set t.inventories ~key:player_id ~data:rest;
    Ok ()
  | None ->
    Or_error.error_s
      [%message
        "powerup is not in your inventory"
          (powerup : Powerup.t)
          (inventory : Powerup.t list)]
;;

let add_effect t player_id (kind : Effect.Kind.t) ~seconds =
  let car = car_exn t player_id in
  car.effects <- (kind, expiry ~now:t.tick ~seconds) :: car.effects
;;

(* {2 Powerups} *)

let use_powerup t player_id (powerup : Powerup.t) =
  let open Or_error.Let_syntax in
  let%bind () = ensure_racing t in
  let%bind { Membership.role; _ } = membership t player_id in
  match role with
  | Track_player ->
    Or_error.error_string
      "track players grant powerups to their driver (assist_teammate) \
       rather than using them"
  | Driver ->
    let car = car_exn t player_id in
    let timed_effect ~seconds =
      let%bind () = take_from_inventory t player_id powerup in
      add_effect t player_id (Powerup powerup) ~seconds;
      Ok ()
    in
    (match powerup with
     | Speed_boost -> timed_effect ~seconds:speed_boost_seconds
     | Invincibility -> timed_effect ~seconds:invincibility_seconds
     | Glider -> timed_effect ~seconds:glider_seconds
     | Flashlight -> timed_effect ~seconds:flashlight_seconds
     | Axe ->
       let%bind () = take_from_inventory t player_id powerup in
       (* Instant counter: cut every vine currently on the car. *)
       car.effects
       <- List.filter car.effects ~f:(fun (kind, (_ : Tick.t)) ->
            match kind with Vines -> false | Powerup _ | Mud_bomb -> true);
       Ok ()
     | Flame_magic ->
       let ice =
         Map_state.features_near
           t.track
           ~map:t.map
           ~center:car.position
           ~radius:flame_magic_radius
         |> List.filter ~f:(fun feature ->
           match Feature.kind feature with
           | Ice_patch -> true
           | Bridge | Gate | Stalactite -> false)
       in
       (match ice with
        | [] ->
          (* Not consumed: wasting the counter on a misclick would feel
             terrible at race speed. *)
          Or_error.error_string "no ice within reach to melt"
        | _ :: _ ->
          let%bind () = take_from_inventory t player_id powerup in
          List.iter ice ~f:(fun (feature : Feature.t) ->
            (* [melt_ice] only fails on a stale id; we just looked these up,
               so a failure is a bug worth crashing on. *)
            let track, (_ : Map_state.Update.t list) =
              ok_exn (Map_state.melt_ice t.track ~id:feature.id)
            in
            t.track <- track);
          Ok ()))
;;

(* {2 Sabotage} *)

(* The map reports facts; the game loop owns consequences ("Facts, not
   consequences", doc/map-design.md). The one event-shaped consequence is
   stalactite impact — stun whoever is under the debris the moment it lands.
   Bridges are positional instead: falling is the per-tick gap check in
   [step_one_car], not a collapse event. *)
let react_to_map_updates t updates =
  List.iter updates ~f:(fun (update : Map_state.Update.t) ->
    match update with
    | Removed (_ : Feature_id.t) -> ()
    | Set feature ->
      (match feature.payload with
       | Stalactite { phase = Debris _ } ->
         Hashtbl.iter t.cars ~f:(fun car ->
           let cell = Game_map.cell_at t.map car.position in
           if List.mem feature.cells cell ~equal:Cell.equal
           then Car_state.stun car)
       | Stalactite { phase = Hanging | Falling _ }
       | Bridge _ | Gate _ | Ice_patch _ ->
         ()))
;;

let validated_victim t ~actor_team ~victim =
  let open Or_error.Let_syntax in
  let%bind { Membership.role; team = victim_team; _ } =
    membership t victim
  in
  match role with
  | Track_player ->
    Or_error.error_s
      [%message
        "target is a track player, not a driver" (victim : Player_id.t)]
  | Driver ->
    if Team_id.equal victim_team actor_team
    then Or_error.error_string "cannot sabotage your own driver"
    else Ok (car_exn t victim)
;;

let use_interference t player_id (sabotage : Rpc_protocol.Sabotage.t) =
  let open Or_error.Let_syntax in
  let%bind () = ensure_racing t in
  let%bind { Membership.role; team = actor_team; _ } =
    membership t player_id
  in
  match role with
  | Driver -> Or_error.error_string "only track players can sabotage"
  | Track_player ->
    (match sabotage with
     | Track action ->
       let%bind track, updates =
         Map_state.apply_action t.track ~map:t.map ~action ~now:t.tick
       in
       t.track <- track;
       react_to_map_updates t updates;
       Ok ()
     | Car Slick_track ->
       (* Superseded by the positioned ice feature once the map landed; kept
          in [Interference.t] because other work depends on that type as-is. *)
       Or_error.error_string
         "Slick_track is superseded: send Track (Place_ice _) instead"
     | Car (Vines victim) ->
       let%bind car = validated_victim t ~actor_team ~victim in
       let environment =
         Game_map.environment_at t.map (Game_map.cell_at t.map car.position)
       in
       (match environment with
        | Castle | Cave ->
          (* environment.mli: vines are a forest power. *)
          Or_error.error_s
            [%message
              "vines only grow in the forest" (environment : Environment.t)]
        | Forest ->
          if Car_state.has_effect car (Powerup Invincibility)
          then Ok ()
          else (
            add_effect t victim Vines ~seconds:vines_seconds;
            Ok ()))
     | Car (Mud_bomb victim) ->
       let%bind car = validated_victim t ~actor_team ~victim in
       if Car_state.has_effect car (Powerup Invincibility)
       then Ok ()
       else (
         add_effect t victim Mud_bomb ~seconds:mud_bomb_seconds;
         Ok ()))
;;

let assist_teammate t player_id powerup =
  let open Or_error.Let_syntax in
  let%bind { Membership.role; team; _ } = membership t player_id in
  match role with
  | Driver ->
    Or_error.error_string
      "only track players hold stock to grant; drivers use what they are \
       given"
  | Track_player ->
    (match Hashtbl.find t.teams team with
     | None -> Or_error.error_string "your driver has not joined yet"
     | Some full_team ->
       let%bind () = take_from_inventory t player_id powerup in
       Hashtbl.update t.inventories full_team.driver.id ~f:(fun inventory ->
         powerup :: Option.value inventory ~default:[]);
       Ok ())
;;

(* {2 Input and time} *)

let set_driver_input t player_id input =
  match Hashtbl.find t.memberships player_id with
  | Some { Membership.role = Driver; _ } ->
    (car_exn t player_id).input <- input
  | Some { Membership.role = Track_player; _ } | None -> ()
;;

let checkpoint_count t = Array.length (Game_map.checkpoints t.map)

let respawn_pose t (progress : Checkpoint.Progress.t) =
  let count = checkpoint_count t in
  (* The checkpoint this car most recently touched — one before the one it is
     hunting, wrapping at the start/finish line. *)
  let last_touched = (progress.next_index - 1 + count) mod count in
  (Game_map.checkpoints t.map).(last_touched).respawn
;;

let step_one_car t ~now (car : Car_state.t) =
  car.effects
  <- List.filter car.effects ~f:(fun ((_ : Effect.Kind.t), expires_at) ->
       Tick.( < ) now expires_at);
  let position, velocity =
    Physics.step
      ~position:car.position
      ~velocity:car.velocity
      ~input:car.input
      ~effect_kinds:(List.map car.effects ~f:fst)
      ~traction:(Map_state.traction_at t.track ~map:t.map car.position)
      ~is_solid:(fun position ->
        Surface.is_solid (Map_state.surface_at t.track ~map:t.map position))
      ~dt:tick_duration
  in
  car.position <- position;
  car.velocity <- velocity;
  (* A collapsed bridge is a gap: gliding cars cross, the rest fall and
     restart at the last checkpoint they touched. *)
  if Map_state.is_gap t.track ~map:t.map (Game_map.cell_at t.map position)
     && not (Car_state.has_effect car (Powerup Glider))
  then (
    let pose = respawn_pose t car.progress in
    car.position <- pose.pos;
    car.velocity
    <- Velocity.stationary ~facing:(Heading.of_radians_exn pose.heading));
  match
    Game_map.checkpoint_at t.map (Game_map.cell_at t.map car.position)
  with
  | None -> ()
  | Some touched ->
    let progress, outcome =
      Checkpoint.Progress.on_touch
        car.progress
        ~checkpoint_count:(checkpoint_count t)
        ~touched
    in
    car.progress <- progress;
    (match outcome with
     | `Advanced | `Ignored -> ()
     | `Lap_completed ->
       if progress.laps_completed >= Game_map.laps_to_win t.map
       then t.race <- Finished)
;;

let step t =
  let now = Tick.next t.tick in
  t.tick <- now;
  (match t.race with
   | Countdown { green_at } ->
     if Tick.( <= ) green_at now then t.race <- Racing
   | Waiting | Racing | Finished -> ());
  (* Map timers run in every phase: a gate shut at the finish still reopens
     while the podium waits. *)
  let track, updates = Map_state.tick t.track ~now in
  t.track <- track;
  react_to_map_updates t updates;
  match t.race with
  | Waiting | Countdown _ | Finished -> ()
  | Racing -> Hashtbl.iter t.cars ~f:(fun car -> step_one_car t ~now car)
;;

(* {2 The read side} *)

let remaining_span ~now ~expires_at =
  Time_ns.Span.scale_int
    tick_duration
    (Tick.to_int expires_at - Tick.to_int now)
;;

let snapshot t : Rpc_protocol.Game_snapshot.t =
  let now = t.tick in
  let per_car ~f =
    Hashtbl.to_alist t.cars
    |> List.map ~f:(fun (player_id, car) -> player_id, f car)
    |> Player_id.Map.of_alist_exn
  in
  { tick = now
  ; race_status = Race.to_status t.race
  ; players =
      List.rev_map t.join_order_rev ~f:(fun player_id ->
        let { Membership.player; team; role } =
          Hashtbl.find_exn t.memberships player_id
        in
        { Rpc_protocol.Player_info.player; team; role })
  ; teams =
      Hashtbl.to_alist t.teams
      |> List.sort ~compare:(fun (a, _) (b, _) -> Team_id.compare a b)
      |> List.map ~f:snd
  ; cars =
      per_car ~f:(fun car ->
        { Rpc_protocol.Car.position = car.position
        ; velocity = car.velocity
        ; progress = car.progress
        })
  ; track = t.track
  ; effects =
      per_car ~f:(fun car ->
        List.map car.effects ~f:(fun (kind, expires_at) ->
          { Effect.kind; remaining = remaining_span ~now ~expires_at }))
  ; inventories =
      Hashtbl.to_alist t.inventories |> Player_id.Map.of_alist_exn
  }
;;
