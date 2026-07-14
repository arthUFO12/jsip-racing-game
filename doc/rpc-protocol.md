# RPC protocol — server/client communication

The server owns all game state, authoritatively. Every tick it pushes the
**entire game state** to every client via `game_feed_rpc`. Clients hold no
state of their own: they render the latest snapshot and send inputs/intents.
If a client crashes and reconnects, the next snapshot restores it fully — no
catch-up logic needed.

Types like `Car.t`, `Track.t`, `Powerup.t` are placeholders — they live in
`lib/types` and aren't implemented yet.

## RPC definitions

Follows the same pattern as jsip-exchange's `lib/protocol/rpc_protocol.ml`:
plain values of `Rpc.Rpc.t` / `Rpc.Pipe_rpc.t`, transport-agnostic via
`Async_rpc_kernel`.

```ocaml
open! Core
open Racing_types
module Rpc = Async_rpc_kernel.Rpc

(** Join as a named player on a team, as [Driver] or [Track_player].
    Returns the server-assigned [Player_id.t] that tags this player in
    every snapshot. Errors: name taken, team full, role claimed. *)
val join_game_rpc : (Join_request.t, Player_id.t Or_error.t) Rpc.Rpc.t

(** THE feed: the server pushes one complete [Game_snapshot.t] per tick.
    Not a delta — the whole state, every time. Clients just render the
    most recent one. *)
val game_feed_rpc : (unit, Game_snapshot.t, Error.t) Rpc.Pipe_rpc.t

(** Driver input: desired heading and throttle, sent every input tick.
    A pure intent — the server clamps it through physics and active
    powerdowns; the result appears in the next snapshot. Fire-and-forget
    ([One_way]) because at input-stream rates there is nothing useful to
    do with a per-message response. *)
val driver_input_rpc : Driver_input.t Rpc.One_way.t

(** Driver uses a held powerup (glider, flame, flashlight, axe).
    Errors: not in inventory, race not running. *)
val use_powerup_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t

(** Track player invokes interference: collapse a bridge, close a gate,
    stalactites, slick, vines/mud-bomb a target. Errors: not available,
    invalid target, on cooldown. *)
val use_interference_rpc : (Interference.t, unit Or_error.t) Rpc.Rpc.t

(** Track player grants a counter-powerup to their own driver. *)
val assist_teammate_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t
```

## Supporting types (sketches)

```ocaml
module Role = struct
  type t =
    | Driver
    | Track_player
end

module Join_request = struct
  type t =
    { name : string
    ; team : Team_id.t
    ; role : Role.t
    }
end

module Game_snapshot = struct
  type t =
    { tick        : Tick.t                        (* monotonic; drop stale ones *)
    ; race_status : Race_status.t                 (* countdown / racing / finished *)
    ; players     : Player_info.t list            (* names, roles, teams, laps *)
    ; cars        : Car.t Player_id.Map.t         (* position, velocity, visual state *)
    ; track       : Track.t                       (* walls, bridges, gates, caves — current truth *)
    ; effects     : Effect.t list Player_id.Map.t (* active power(up|down)s w/ remaining time *)
    ; inventories : Powerup.t list Player_id.Map.t
    }
end

module Driver_input = struct
  type t =
    { heading  : Heading.t
    ; throttle : Throttle.t
    }
end

module Interference = struct
  type t =
    | Collapse_bridge of Bridge_id.t
    | Close_gate of Gate_id.t
    | Drop_stalactites of Cave_section_id.t
    | Slick_track of Track_position.t
    | Vines of Player_id.t
    | Mud_bomb of Player_id.t
end
```

## Design notes

- **No `get_state`-style RPCs, and inputs return `unit` (or nothing).**
  Clients never read state back from request-response calls — if they
  could, there'd be two sources of truth racing each other. Everything
  flows out through the one pipe. Confirmation of an input *is* the next
  snapshot.
- **Sessions replace explicit identity.** No post-join RPC carries the
  *sender's* `Player_id.t` — the server knows who's calling from the
  connection (same as jsip-exchange after `login_rpc`). This prevents
  spoofing another driver's input. Only *victims* of targeted
  interference appear as `Player_id.t` payloads.
- **`tick` enables "latest wins".** A client that falls briefly behind
  should render the newest snapshot and skip stale ones, not queue them.
  A monotonic tick makes "is this newer?" trivial.
- **State-sync vs. delta-sync trade-off.** Full snapshots buy simplicity
  and self-healing (a dropped message costs nothing — the next snapshot
  supersedes it) at the price of bandwidth scaling with world size
  rather than change size. For this game's size (a handful of cars, one
  track) snapshots win easily.
- **Visibility split is server-side.** The driver sees only part of the
  track; the track player sees ahead. If the full snapshot goes to
  everyone, the driver's client *has* the whole track and merely chooses
  not to draw it — a cheating client could show it. If that matters, the
  server sends role-filtered snapshots (still full snapshots — just of
  what that role is allowed to know).
