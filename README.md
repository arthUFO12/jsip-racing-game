# jsip-racing-game

A networked, two-players-per-team racing game written in OCaml, built as a
JSIP teaching project. Each team is a **driver** and a **track player**: the
driver steers a car but can only see the track right around them, while the
track player sees the whole course and helps their driver — warning them of
what's ahead, granting power-ups, and sabotaging rival teams by reshaping the
track itself (collapsing bridges, closing castle gates, dropping stalactites,
icing the road).

The design intent is a server that owns all game logic and streams the full
state to thin clients over `Async_rpc`; the clients render with OCaml's
`Graphics` library and send back only inputs. See
[`spec.md`](spec.md) for the gameplay brainstorm and
[`doc/`](doc) for the subsystem designs.

## Project status

This is a **starter codebase, early in construction.** The shared *vocabulary*
of the game is built and tested; the systems that consume it — physics, the
game loop, the network protocol, the runnable client and server — are not
here yet. There is **no playable game to run today**; `dune build` produces
libraries, not a binary.

The code is the source of truth (see [Design docs](#design-docs) below for
where the prose has drifted). Concretely:

| Component | Where | State |
|---|---|---|
| `racing_types` — core domain types | `lib/types/` | **Complete and tested** |
| `racing_map` — track model | `lib/map/` | Interfaces + data types done; race logic **stubbed** |
| `jsip_client` — input handling | `app/client/src/` | `Input` module **complete** |
| RPC protocol library | — | Sketched in [`doc/rpc-protocol.md`](doc/rpc-protocol.md), **not built** |
| Cars / physics / game loop | — | Not started |
| Server & client binaries | `app/{server,client}/bin/` | Empty placeholder files |

## Building, testing, formatting

Standard external-opam `dune`:

```sh
dune build                 # compile the libraries
dune runtest               # run the expect tests
dune fmt --auto-promote    # format (.ocamlformat: janestreet profile, margin 77)
dune build @doc            # generate odoc HTML
```

`dune build` and `dune runtest` both pass. There is nothing to `dune exec`
yet — the two files under `app/*/bin/` are empty and have no `dune` file, so
no executable is produced. (The opam dependencies already list `async`,
`async_rpc_kernel`, `core_bench`, etc.; those are provisioned for work that
hasn't landed — the current libraries depend only on `core`, plus `graphics`
in the client.)

## Repository layout

```
lib/
  types/            racing_types  — the domain vocabulary (done, tested)
    test/           expect tests for the validating types
  map/              racing_map    — the track model (data types done, logic stubbed)
app/
  client/
    src/            jsip_client   — keyboard/mouse input over Graphics (done)
    bin/main.ml     client executable — empty placeholder
  server/
    bin/main.ml     server executable — empty placeholder
doc/
  map-design.md     design + rationale for lib/map
  rpc-protocol.md   sketch of the server/client RPCs (partly stale — see below)
spec.md             one-day gameplay brainstorm (open questions marked [OPEN])
```

## The libraries

A theme runs through all of these: **make illegal states unrepresentable, and
validate human input once at the edge.** A `Heading.t` is always normalized, a
`Speed.t` is never negative, a `Team.t` cannot hold two drivers, a
`Feature.t` cannot be a gate stuck in a bridge's phase. Downstream code then
never re-checks these things.

### `racing_types` (`lib/types/`)

Plain data shared by the server, both clients, and the protocol — no game
logic, just types and the smart constructors that keep bad values out. The
top-level module [`Racing_types`](lib/types/racing_types.ml) re-exports:

- **People** — `Player_id`, `Player_name`, `Player`, `Role`, `Team_id`,
  `Team`. A player's role isn't a stored field: it's *which slot* they occupy
  in their `Team.t` (`driver` or `track_player`), so "a team with two drivers"
  can't be written down. `Team.create` rejects a team whose two slots are the
  same player; `Player_name.of_string` enforces the naming rules (1–16 chars,
  letters/digits/`_`/`-`) and reports *every* broken rule, not just the first.
- **Motion** — `Position`, `Heading`, `Speed`, `Velocity`, `Driver_input`.
  `Velocity` is polar (heading + non-negative speed), so "negative speed vs.
  flipped heading" ambiguity never arises. `Driver_input` is the WASD key
  state (`accelerate`/`brake`/`steer_left`/`steer_right`) — pure intent that
  the server integrates into physics.
- **Items & sabotage** — `Powerup` (`Speed_boost`, `Invincibility`, and the
  four counters `Glider`/`Flame_magic`/`Flashlight`/`Axe`), `Interference`
  (the car-targeting sabotage — `Slick_track`, `Vines`, `Mud_bomb`), and
  `Effect` (a timed thing acting on one driver, with server-computed
  `remaining` time).
- **Race bookkeeping** — `Tick` (monotonic snapshot counter; clients drop
  stale ones) and `Race_status` (`Countdown`/`Racing`/`Finished`).

Tested with expect tests under `lib/types/test/` (`Heading` normalization and
junk rejection, `Player_name` validation, `Speed`, `Team` shape, `Tick`
monotonicity).

### `racing_map` (`lib/map/`)

The track: the immutable layout plus the live state of everything a track
player can sabotage. Linked by both the server (authoritative state, physics
queries) and the client (a replica to render), so it depends on `core` only —
no `graphics`, no networking. Two types carry the whole story:

- **`Game_map.t`** — the immutable, validated layout: a `Road`/`Wall`/`Trees`
  surface grid, a `Forest`/`Castle`/`Cave` environment grid, ordered
  checkpoints, the start grid, and the initial features. Loaded once from a
  human-authored sexp file and sent to each client at join.
- **`Map_state.t`** — the live feature table. The server transitions it with
  pure functions and broadcasts the result each tick.

A `Feature.t` (bridge, gate, stalactite, ice patch) carries both its
parameters *and* its current phase in one payload, and every hostile action
passes through a still-drivable **telegraph phase** (`Collapsing`, `Closing`,
`Falling`) — that window is exactly what a track player watches for to warn
their driver. The map states *facts* (`surface_at`, `is_gap`, `traction_at`,
`viewport`); physics owns the *consequences* (who falls, who's stunned).
Geometry is a grid world with free-moving cars: terrain is O(1) cell lookups,
cars keep continuous `Vec2.t` positions, y-up with the origin bottom-left to
match the `Graphics` window.

**Implemented today:** the pure data types and helpers — `Vec2`, `Cell`
(including `of_vec2`/`center`/`in_radius`), `Pose`, `Tick`, `Surface`,
`Environment`, `Feature_id`, `Feature` (`kind`, `surface_override`, `is_gap`,
`traction_multiplier`), `Track_action`, the `Game_map` accessors, and
`Map_state.create`/`apply_update`/`feature`/`features`.

**Still stubbed** (`failwith "TODO: ..."`, each with an "expected shape"
comment): `Game_map.load` (sexp parse + validation), the `Map_state`
transitions (`apply_action`, `tick`, `melt_ice`), the composed terrain
queries (`surface_at`, `is_blocked`, `is_gap`, `traction_at`, `features_near`,
`viewport`), and `Checkpoint.Progress.on_touch`. This library has no tests
yet; [`doc/map-design.md`](doc/map-design.md) records the intended
implementation and a test plan for when the stubs are filled in.

### `jsip_client` (`app/client/src/`)

Currently just [`Input`](app/client/src/input.ml): a per-frame dispatch layer
over the polling `Graphics` input API. Call `Input.poll` once per render tick
and it drains pending keyboard/mouse events, firing the handlers you
registered with `on_keypress`/`on_click`. It surfaces only what the game
cares about — WASD, digits `0`–`9`, and clicks — and synthesizes held-key
state (`is_pressed`) from OS auto-repeat, since `Graphics` delivers no
key-release events. The `.mli` documents the two consequences of that trick
(a late-observed release, and X11 auto-repeating only the newest key).

## Design docs

[`spec.md`](spec.md) is the gameplay brainstorm (win conditions, the
power-up/power-down table, role-switching — many points still marked
`[OPEN]`). [`doc/map-design.md`](doc/map-design.md) documents the map
subsystem and is kept in step with the code. [`doc/rpc-protocol.md`](doc/rpc-protocol.md)
sketches the intended server/client RPCs.

**These docs are a starting point, not authority — the `.ml`/`.mli` files
win.** A few places where the prose has already drifted from the code:

- **Driver input.** `doc/rpc-protocol.md` sketches a `{ heading; throttle }`
  input; the actual `Driver_input.t` is the four WASD booleans. The doc's
  version is superseded.
- **Interference.** `doc/rpc-protocol.md` lists all sabotage under one
  `Interference.t`. In the code it's split: the *car*-targeting cases live in
  `Racing_types.Interference.t` (`Slick_track`, `Vines`, `Mud_bomb`), and the
  *track*-targeting cases live in `Racing_map.Track_action.t`
  (`Collapse_bridge`, `Close_gate`, `Drop_stalactite`, `Place_ice`).
- **Role naming.** `spec.md` and `doc/rpc-protocol.md` call the second role
  the "copilot"; the code calls it `Track_player`. (`spec.md` also claims the
  roles live in `player.mli`; they're actually in `role.ml`, and `Player.t`
  deliberately has no role field.)
- **The protocol isn't built.** `doc/rpc-protocol.md` is a design sketch —
  there is no protocol library, and the `Car.t` / `Track.t` types it
  references don't exist yet (the track's live state is `Racing_map.Map_state.t`).
- **Two `Tick`s.** `Racing_types.Tick` and `Racing_map.Tick` are separate,
  identical `int`-backed modules; merging them is open question #9 in
  `doc/map-design.md`.

## What's next

Roughly, to reach something playable: fill in the `racing_map` stubs and add
its tests; introduce car/physics and a game-loop; build the RPC protocol
library from `doc/rpc-protocol.md` (reconciled with the types above); and wire
up the server and client binaries.
