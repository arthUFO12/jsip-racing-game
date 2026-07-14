(** Server-side integration of driver intent into car motion, one tick at a
    time. Pure functions of their arguments: terrain comes in as facts
    ([traction], [is_solid]) queried from {!Racing_map.Map_state} by the
    caller, so this module never sees the map itself ("the map states facts
    and physics owns consequences" — [lib/map/surface.mli]).

    The tuning constants are exposed so clients can render honestly (a boost
    gauge, a speedometer scaled to [max_speed]) and tests can compute
    expected values. Anti-tunneling constraint from [doc/map-design.md]: a
    car must never cross more than ~one cell per tick, so keep [max_speed]
    (times any boost) safely below [cell_size * Game_state.ticks_per_second]
    world units per second. *)

open! Core
open Racing_types

(** {2 Tuning constants} *)

(** world units per second, unboosted ceiling *)
val max_speed : float

(** u/s² while holding accelerate *)
val acceleration : float

(** u/s² while holding brake *)
val brake_deceleration : float

(** u/s² while coasting, keys released *)
val drag_deceleration : float

(** radians per second at full steer *)
val turn_rate : float

(** scales [max_speed] under Speed_boost *)
val speed_boost_multiplier : float

(** scales [max_speed] under Vines *)
val vines_speed_multiplier : float

(** {2 The step} *)

(** Where the car points after [dt] of this input. Steering is arcade-style:
    it turns at [turn_rate] even when parked, and opposite keys cancel.
    Normalization is {!Heading}'s job, so wrap-around never leaks out. *)
val next_heading
  :  Heading.t
  -> input:Driver_input.t
  -> dt:Time_ns.Span.t
  -> Heading.t

(** How fast the car moves after [dt] of this input, given what's acting on
    the car: [effect_kinds] are its active effects (speed boost, vines — see
    {!Racing_types.Effect.Kind}), [traction] is
    {!Racing_map.Map_state.traction_at} under the car ([1.0] on clean road,
    [< 1.0] on ice). Never negative and never above the effective ceiling —
    reversing is a flipped heading, not a negative speed ({!Speed}). *)
val next_speed
  :  Speed.t
  -> input:Driver_input.t
  -> effect_kinds:Effect.Kind.t list
  -> traction:float
  -> dt:Time_ns.Span.t
  -> Speed.t

(** One tick of motion: turn, change speed, advance, and stop dead at solid
    terrain ([is_solid] sampled at the destination — v1 collision is "bonk":
    position stays, speed zeroes, heading keeps). *)
val step
  :  position:Position.t
  -> velocity:Velocity.t
  -> input:Driver_input.t
  -> effect_kinds:Effect.Kind.t list
  -> traction:float
  -> is_solid:(Position.t -> bool)
  -> dt:Time_ns.Span.t
  -> Position.t * Velocity.t
