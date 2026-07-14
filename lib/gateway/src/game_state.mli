(** The authoritative world — everything spec.md says the server keeps: every
    player and their details (names, roles, teams, laps), where every car is
    and how it is moving, the live state of every track powerdown with its
    timers ({!Racing_map.Map_state.t}), and the race lifecycle.

    Mutation comes in exactly two flavors:

    - {e Commands} from clients ([join], [use_powerup], ...) — validated here
      (permissions, inventory, targets) and answered with [unit Or_error.t];
      an [Error] is a normal game event, not a crash.
    - {e Time}: [step] advances the world one {!Racing_types.Tick.t} — fires
      map timers, expires effects, integrates {!Physics} for every car, and
      settles falls, checkpoints, laps and the finish.

    Reads are [snapshot], the complete statement of mutable state that
    {!Server} broadcasts every tick. No other reads exist, on purpose: if
    clients could query pieces, there would be two sources of truth racing
    each other (see [doc/rpc-protocol.md]).

    Trust boundary: callers pass whatever a client sent; every rule check
    lives behind these functions, so the RPC layer stays a dumb pipe. *)

open! Core
open Racing_types
open Racing_map

type t

(** {2 The game clock}

    [step] represents [tick_duration] of game time; {!Server} calls it that
    often. Gameplay durations ("vines last 4 seconds") are converted to
    absolute expiry ticks here — this module owns the tick rate (see
    tick.mli's "whoever owns the tick rate"). *)

val ticks_per_second : int
val tick_duration : Time_ns.Span.t

(** {2 Setup} *)

val create : map:Game_map.t -> t

(** The immutable layout, exactly as passed to {!create} — the server hands
    it to each client once, in the {!Rpc_protocol.Joined.t} response. *)
val game_map : t -> Game_map.t

(** {2 Commands from clients}

    Callers identify players by {!Player_id.t}; the RPC layer derives it from
    the connection, never from the payload. *)

(** Take a seat. Drivers spawn on the next free {!Game_map.start_grid} slot;
    track players start with one of every {!Powerup.t} in stock. When a join
    completes a pair, the {!Team.t} forms — and the first complete team
    starts the race countdown. Errors: invalid name, seat taken, start grid
    full. *)
val join : t -> Rpc_protocol.Join_request.t -> Player_id.t Or_error.t

(** Latest key state wins; the next [step] integrates it. Silently ignores
    non-drivers and unknown players — this backs a one-way RPC, so there is
    no error channel, and dropping a hostile client's noise is the safe
    default. *)
val set_driver_input : t -> Player_id.t -> Driver_input.t -> unit

(** Driver spends a held powerup: [Speed_boost]/[Invincibility]/[Glider]/
    [Flashlight] become timed {!Effect.t}s; [Axe] instantly cuts vines;
    [Flame_magic] melts ice patches within reach (and is not consumed if
    there are none). Requires a running race. *)
val use_powerup : t -> Player_id.t -> Powerup.t -> unit Or_error.t

(** Track player sabotages: [Track] actions go through
    {!Map_state.apply_action} (which validates ids, kinds and phases); [Car]
    interference needs a rival driver — vines additionally need the victim to
    be in forest, and both bounce off [Invincibility] (that is an [Ok]: the
    attempt was legal, the effect just failed). Requires a running race. *)
val use_interference
  :  t
  -> Player_id.t
  -> Rpc_protocol.Sabotage.t
  -> unit Or_error.t

(** Track player moves a powerup from their stock into their own driver's
    inventory. Allowed in any race phase — stocking up during the countdown
    is part of the game. Errors: not a track player, not in stock, driver
    hasn't joined yet. *)
val assist_teammate : t -> Player_id.t -> Powerup.t -> unit Or_error.t

(** {2 Time and reads} *)

(** One tick: advance the clock, fire {!Map_state.tick} timers and react
    (stalactite debris stuns the cars under it), and — while the race runs —
    integrate every car (physics, walls, ice), drop non-gliding cars through
    gaps to their last checkpoint's respawn, and advance checkpoint/lap
    progress until someone wins. *)
val step : t -> unit

val snapshot : t -> Rpc_protocol.Game_snapshot.t
