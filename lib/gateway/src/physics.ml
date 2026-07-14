open! Core
open Racing_types

(* Tuning: with 30 ticks/s and 1.0-unit cells, speeds must stay well below
   30 u/s or cars tunnel through one-cell walls (doc/map-design.md,
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
       both steering keys cancels to zero, like the spec's "opposing keys
       are fine" rule for [Driver_input.t]. *)
    (if input.steer_left then 1. else 0.)
    -. (if input.steer_right then 1. else 0.)
  in
  Heading.of_radians_exn
    (Heading.to_radians heading
     +. (direction *. turn_rate *. Time_ns.Span.to_sec dt))
;;

(* TODO(human): implement [next_speed] — the acceleration model of the whole
   game. The contract is in physics.mli; the ingredients:

   - [input.accelerate] / [input.brake]: push toward the ceiling / toward
     zero using [acceleration] / [brake_deceleration]; with neither held,
     bleed speed with [drag_deceleration]. A change in speed over a tick is
     "rate *. Time_ns.Span.to_sec dt".
   - The ceiling: [max_speed], scaled by [speed_boost_multiplier] when
     [effect_kinds] contains [Effect.Kind.Powerup Speed_boost] and by
     [vines_speed_multiplier] when it contains [Vines] (decide how they
     stack — multiply? strongest wins?).
   - [traction]: how does ice change things — scale the ceiling, the
     acceleration, or both? (This is why braking on ice is scary.)
   - Clamp into [0 .. ceiling] and build the result with
     [Speed.of_float_exn] (your arithmetic on finite floats stays finite).

   [Speed.to_float] gets you a float from the current speed. *)
let next_speed
  (_ : Speed.t)
  ~input:(_ : Driver_input.t)
  ~effect_kinds:(_ : Effect.Kind.t list)
  ~traction:(_ : float)
  ~dt:(_ : Time_ns.Span.t)
  =
  failwith "TODO: implement Physics.next_speed"
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
