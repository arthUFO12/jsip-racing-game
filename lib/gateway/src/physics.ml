open! Core
open Racing_types

(* Tuning: with 30 ticks/s and 1.0-unit cells, speeds must stay well below 30
   u/s or cars tunnel through one-cell walls (doc/map-design.md,
   "Anti-tunneling"). Boosted ceiling here is 12 * 1.5 = 18 u/s. *)
let max_speed = 12.
let acceleration = 8.
let brake_deceleration = 14.
let drag_deceleration = 4.
let turn_rate = Float.pi
let speed_boost_multiplier = 1.5
let vines_speed_multiplier = 0.4

let next_heading heading ~(input : Driver_input.t) ~dt =
  let direction =
    (* Counterclockwise-positive frame (heading.mli): A turns left. Holding
       both steering keys cancels to zero, like the spec's "opposing keys are
       fine" rule for [Driver_input.t]. *)
    (if input.steer_left then 1. else 0.)
    -. if input.steer_right then 1. else 0.
  in
  Heading.of_radians_exn
    (Heading.to_radians heading
     +. (direction *. turn_rate *. Time_ns.Span.to_sec dt))
;;

let next_speed speed ~(input : Driver_input.t) ~effect_kinds ~traction ~dt =
  let has kind = List.mem effect_kinds kind ~equal:Effect.Kind.equal in
  let ceiling =
    (* Multipliers apply by presence, not count: stacking a second boost
       extends nothing here (duration is the game loop's business) and can
       never compound past the anti-tunneling cap. Boost and vines combine
       multiplicatively — a boosted, vined car does 12 * 1.5 * 0.4 = 7.2 u/s:
       the boost helps, the vines still hurt. The clamp below also makes
       vines bite instantly (spec.md: "reduces speed by X%"), rather than
       waiting for drag to bleed the excess off. *)
    max_speed
    *. (if has (Powerup Speed_boost) then speed_boost_multiplier else 1.)
    *. if has Vines then vines_speed_multiplier else 1.
  in
  let rate =
    (* Brake wins when both pedals are held — panic-friendly. Pedals push
       through the tires, so ice ([traction] < 1) dulls both: sluggish to
       speed up, scary to stop. Drag is air and rolling resistance and
       ignores traction — even on ice, a coasting car settles. *)
    match input.brake, input.accelerate with
    | true, true | true, false -> -.brake_deceleration *. traction
    | false, true -> acceleration *. traction
    | false, false -> -.drag_deceleration
  in
  Speed.of_float_exn
    (Float.clamp_exn
       (Speed.to_float speed +. (rate *. Time_ns.Span.to_sec dt))
       ~min:0.
       ~max:ceiling)
;;

let step
  ~position
  ~(velocity : Velocity.t)
  ~input
  ~effect_kinds
  ~traction
  ~is_solid
  ~dt
  =
  let heading = next_heading velocity.heading ~input ~dt in
  let speed = next_speed velocity.speed ~input ~effect_kinds ~traction ~dt in
  let distance = Speed.to_float speed *. Time_ns.Span.to_sec dt in
  let angle = Heading.to_radians heading in
  let destination =
    Position.add
      position
      { x = distance *. Float.cos angle; y = distance *. Float.sin angle }
  in
  if is_solid destination
  then position, { Velocity.heading; speed = Speed.zero }
  else destination, { Velocity.heading; speed }
;;
