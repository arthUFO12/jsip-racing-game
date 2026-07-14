# RPC protocol — server/client communication

> **The code is ground truth**: the protocol lives in
> `lib/gateway/src/rpc_protocol.mli` (types and RPCs, with doc comments)
> and is served by `lib/gateway/src/server.ml`. This doc explains the
> shape and records the reasoning; when they disagree, trust the `.mli`.

The server owns all game state, authoritatively. Every tick
(`Game_state.tick_duration`, 30 ticks/s) it pushes the **entire mutable
game state** to every subscriber via `game_feed_rpc`. Clients hold no
state of their own: they render the latest snapshot and send
inputs/intents. If a client crashes and reconnects, the next snapshot
restores it fully — no catch-up logic needed.

The one deliberate exception is the immutable track layout
(`Racing_map.Game_map.t`): its grids are big and never change, so it is
sent **once**, in the `join_game_rpc` response, instead of riding in
every snapshot (see "Protocol fit" in `doc/map-design.md`). Everything
that changes during a race — bridge/gate/stalactite/ice state — is
`Racing_map.Map_state.t`, and that *is* in every snapshot.

## The RPCs

```ocaml
(* lib/gateway/src/rpc_protocol.mli, abridged *)
val join_game_rpc : (Join_request.t, Joined.t Or_error.t) Rpc.Rpc.t
val game_feed_rpc : (unit, Game_snapshot.t, Error.t) Rpc.Pipe_rpc.t
val driver_input_rpc : Driver_input.t Rpc.One_way.t
val use_powerup_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t
val use_interference_rpc : (Sabotage.t, unit Or_error.t) Rpc.Rpc.t
val assist_teammate_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t
```

- **`join_game_rpc`** — take a seat (`{ name : string; team : Team_id.t;
  role : Role.t }`). Teammates agree on a team number out of band; the
  server forms the `Team.t` when both seats fill. Returns `Joined.t =
  { player_id; map }`. Errors: invalid name, seat taken, start grid
  full, connection already joined.
- **`game_feed_rpc`** — THE feed. One complete `Game_snapshot.t` per
  tick. Confirmation of any input is the next snapshot, never a
  response value.
- **`driver_input_rpc`** — the WASD key state (`Driver_input.t`, four
  booleans — *not* the heading+throttle this doc once sketched). Pure
  intent; the server integrates it through physics, terrain and active
  powerdowns. One-way: at input rates there is nothing useful to do
  with a per-message response.
- **`use_powerup_rpc`** — driver spends a held item. Timed effects
  (speed boost, invincibility, glider, flashlight) or instant counters
  (axe cuts vines; flame magic melts nearby ice).
- **`use_interference_rpc`** — track-player sabotage, both kinds in one
  payload (`Sabotage.t` below).
- **`assist_teammate_rpc`** — track player moves a powerup from their
  stock into their own driver's inventory.

## Supporting types (see the `.mli` for the full story)

```ocaml
module Sabotage = struct
  type t =
    | Car of Interference.t      (* vines, mud bomb — car status effects *)
    | Track of Track_action.t    (* collapse bridge, close gate,
                                    drop stalactite, place ice *)
end

module Game_snapshot = struct
  type t =
    { tick        : Tick.t                        (* monotonic; drop stale *)
    ; race_status : Race_status.t                 (* countdown/racing/finished *)
    ; players     : Player_info.t list            (* everyone, join order *)
    ; teams       : Team.t list                   (* completed pairs *)
    ; cars        : Car.t Player_id.Map.t         (* position, velocity, laps *)
    ; track       : Map_state.t                   (* live feature phases *)
    ; effects     : Effect.t list Player_id.Map.t (* with remaining time *)
    ; inventories : Powerup.t list Player_id.Map.t
    }
end
```

`Sabotage.t` is the meeting point of two libraries that cannot see each
other: car-targeted powerdowns are `Racing_types.Interference.t` (domain
vocabulary), map-targeted ones are `Racing_map.Track_action.t`
(validated against feature ids/phases by `Map_state.apply_action`).
Known wart: `Interference.Slick_track` predates the map's positioned
`Place_ice` and is rejected by the server with a pointer to `Track
(Place_ice _)` — the constructor is kept for now because other work
depends on `Interference.t` as-is.

## Design notes

- **No `get_state`-style RPCs, and inputs return `unit` (or nothing).**
  If clients could read state back from request-response calls, there
  would be two sources of truth racing each other. Everything flows out
  through the one pipe; confirmation of an input *is* the next snapshot.
- **Sessions replace explicit identity.** No post-join RPC carries the
  *sender's* `Player_id.t` — the server knows who is calling from the
  connection (`Server.Connection_state`). This prevents spoofing another
  driver's input. Only *victims* of targeted interference appear as
  `Player_id.t` payloads.
- **`tick` enables "latest wins".** A client that falls behind should
  render the newest snapshot and skip stale ones. The server applies the
  same policy on its side: a subscriber with unread snapshots buffered
  gets new ones *skipped, not queued* (`Server.max_buffered_snapshots`),
  so a slow consumer costs bounded memory. (Contrast the unbounded
  `write_without_pushback_if_open` smell in jsip-exchange's gateway.)
- **State-sync vs. delta-sync trade-off.** Full snapshots buy simplicity
  and self-healing (a dropped message costs nothing) at the price of
  bandwidth scaling with world size. Splitting the immutable `Game_map`
  out of the snapshot keeps the per-tick payload to the small mutable
  core; if it ever grows too fat, `Map_state.Update.t` +
  `Map_state.apply_update` are the ready-made delta story.
- **Visibility split is client-side for now.** The full snapshot goes to
  everyone; the driver's limited view is rendering policy
  (`Map_state.viewport`). A cheating client could render more than its
  role should see. If that matters, the server sends role-filtered
  snapshots — still full snapshots, just of what that role may know.
