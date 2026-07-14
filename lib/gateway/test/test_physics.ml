open! Core
open Racing_types
open Racing_gateway

(* A fat 100ms dt keeps the numbers round: turn_rate is pi rad/s so one call
   turns pi/10, and the speed rates (8/14/4 u/s²) move speed by 0.8/1.4/0.4
   per call. *)

let dt = Time_ns.Span.of_int_ms 100

let show_turn ~from input =
  let heading = Physics.next_heading from ~input ~dt in
  printf "%.3f rad\n" (Heading.to_radians heading)
;;

let%expect_test "steering turns at [turn_rate], counterclockwise-positive" =
  show_turn ~from:Heading.zero { Driver_input.idle with steer_left = true };
  [%expect {| 0.314 rad |}];
  show_turn
    ~from:(Heading.of_radians_exn Float.pi)
    { Driver_input.idle with steer_right = true };
  [%expect {| 2.827 rad |}]
;;

let%expect_test "steering right from zero wraps into [0, 2pi)" =
  show_turn ~from:Heading.zero { Driver_input.idle with steer_right = true };
  [%expect {| 5.969 rad |}]
;;

let%expect_test "opposite keys cancel; no keys hold the line" =
  let quarter_turn = Heading.of_radians_exn (Float.pi /. 2.) in
  show_turn
    ~from:quarter_turn
    { Driver_input.idle with steer_left = true; steer_right = true };
  [%expect {| 1.571 rad |}];
  show_turn ~from:quarter_turn Driver_input.idle;
  [%expect {| 1.571 rad |}]
;;

let show_speed ?(effect_kinds = []) ?(traction = 1.) ~from input =
  let speed =
    Physics.next_speed
      (Speed.of_float_exn from)
      ~input
      ~effect_kinds
      ~traction
      ~dt
  in
  printf "%.2f u/s\n" (Speed.to_float speed)
;;

let accelerate = { Driver_input.idle with accelerate = true }
let brake = { Driver_input.idle with brake = true }

let%expect_test "pedals: accelerate, coast, brake — and brake wins" =
  show_speed ~from:5. accelerate;
  [%expect {| 5.80 u/s |}];
  show_speed ~from:5. Driver_input.idle;
  [%expect {| 4.60 u/s |}];
  show_speed ~from:5. brake;
  [%expect {| 3.60 u/s |}];
  show_speed ~from:5. { accelerate with brake = true };
  [%expect {| 3.60 u/s |}]
;;

let%expect_test "the ceiling moves with effects and clamps immediately" =
  (* Flat out at max_speed: no gain without a boost... *)
  show_speed ~from:12. accelerate;
  [%expect {| 12.00 u/s |}];
  (* ...room to grow with one. *)
  show_speed
    ~from:12.
    accelerate
    ~effect_kinds:[ Effect.Kind.Powerup Speed_boost ];
  [%expect {| 12.80 u/s |}];
  (* Vines landing on a fast car bite instantly (spec: "reduces speed by
     X%"), not after drag catches up: ceiling is 12 * 0.4 = 4.8. *)
  show_speed ~from:10. Driver_input.idle ~effect_kinds:[ Effect.Kind.Vines ];
  [%expect {| 4.80 u/s |}]
;;

let%expect_test "ice dulls the pedals but not drag" =
  show_speed ~from:5. accelerate ~traction:0.5;
  [%expect {| 5.40 u/s |}];
  show_speed ~from:5. brake ~traction:0.5;
  [%expect {| 4.30 u/s |}];
  show_speed ~from:5. Driver_input.idle ~traction:0.5;
  [%expect {| 4.60 u/s |}]
;;

let%expect_test "step: pull away east, then bonk into a wall" =
  (* Fixed precision on purpose: raw float sexps drip representation noise
     (0.8 *. 0.1 prints as 0.080000000000000016) that says nothing about the
     physics. *)
  let show ((position : Position.t), (velocity : Velocity.t)) =
    printf
      "(%.3f, %.3f) %.2f u/s\n"
      position.x
      position.y
      (Speed.to_float velocity.speed)
  in
  let velocity = Velocity.stationary ~facing:Heading.zero in
  let open_road (_ : Position.t) = false in
  let position, velocity =
    Physics.step
      ~position:Position.origin
      ~velocity
      ~input:accelerate
      ~effect_kinds:[]
      ~traction:1.
      ~is_solid:open_road
      ~dt
  in
  show (position, velocity);
  [%expect {| (0.080, 0.000) 0.80 u/s |}];
  let wall (_ : Position.t) = true in
  let position, velocity =
    Physics.step
      ~position
      ~velocity
      ~input:accelerate
      ~effect_kinds:[]
      ~traction:1.
      ~is_solid:wall
      ~dt
  in
  show (position, velocity);
  [%expect {| (0.080, 0.000) 0.00 u/s |}]
;;
