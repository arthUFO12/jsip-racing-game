# Map subsystem design — `lib/map` (`Racing_map`)

Design notes for the track/map library: what exists, why it is shaped this
way, and what is still open. Interfaces live in `lib/map/*.mli` — **the
code is ground truth**; this doc explains it and records decisions.

## Scope

`Racing_map` owns everything about the track:

- the static layout (grids, checkpoints, start grid, authored features),
- the live state of every dynamic feature (bridges, gates, stalactites,
  ice) and the transitions a track player's sabotage triggers,
- the fact queries physics and rendering ask ("what is under this point?",
  "is this cell blocked?", "what does this driver see?").

It is linked by **both** the server (authoritative state, physics queries)
and the client (rendering data), so it depends on `core` and
`racing_types` only — no `graphics`, no networking. World-coordinate
vocabulary (`Position`, `Tick`) comes from `Racing_types`;
`Cell.of_position` is the bridge from car space to the grid. Non-goals: cars/physics/game loop/RPC (the rest
of the project), car-targeted powerdowns (vines, mud bombs — those are car
status effects; the map's only involvement is `Environment.t` legality),
and the powerup/inventory economy.

## Decisions so far

| Question | Decision |
|---|---|
| Geometry | **Grid world, free cars**: tile grid for terrain/features, continuous `Racing_types.Position.t` for cars |
| Surfaces | `Road \| Wall \| Trees` — no slow/deadly ground; `Wall`/`Trees` differ only in rendering |
| Environments | `Forest \| Castle \| Cave` — theme, darkness (`Cave`), power legality |
| Map format | **Pure sexp file** (grid included as sexp data); parser ≈ free via `[@@deriving sexp]` + validation |
| Map pickups | **None in v1** — inventory economy lives with the track player, off-map |
| Collapsed bridge | A **gap**, not a surface: base cells stay `Road`, `Map_state.is_gap` turns true; gliders cross, others fall (physics' call) |
| Timers | Absolute **`Tick.t` expiries** (server logical clock), never wall-clock |
| Starter deliverable | `.mli` interfaces + stub `.ml`s that build; real logic left as `failwith "TODO"` stubs |

## The shape: static vs. dynamic

Two types, one rule — **`Game_map.t` never changes after `load`;
everything that changes during a race lives in `Map_state.t`.**

- `Game_map.t` — immutable, validated layout. Loaded from a sexp file,
  sent to a client once (it derives `bin_io`), queried for the *base*
  layer.
- `Map_state.t` — the live feature table (`Feature.t Feature_id.Map.t`).
  The server owns the authoritative copy and transitions it with pure
  functions that return the new state **plus `Update.t`s describing what
  changed**.

A `Feature.t`'s payload carries both its per-kind parameters *and* its
current phase (`Bridge of { phase : Intact | Collapsing | Collapsed }`),
so "a gate in a collapsed phase" is unrepresentable and there is no
parallel kind/state table to drift. `Feature.Kind.t` is the one deliberate
mirror (payload-free tags for UI/validation); `Feature.kind` is the single
bridge, and the no-catch-all-match rule plus an `enumerate` expect test
keep it honest.

Per-tick server flow:

1. For each track-player command: `Map_state.apply_action` →
   `Ok (state, updates)` or `Error` (rejected for that player only).
2. `Map_state.tick ~now` fires expired timers → more updates. Features
   that just entered an impact phase (`Debris`, `Collapsed`) prompt the
   game loop to check cars standing in their cells (stun / fall).
3. Physics queries the composed facts: `surface_at`, `is_blocked`,
   `is_gap`, `traction_at`.
4. The snapshot goes out (see "Protocol fit").

## Protocol fit (please read, partner!)

`doc/rpc-protocol.md` pushes a **full `Game_snapshot.t` every tick**, with
a `track : Track.t` placeholder. Suggested split of that placeholder:

- **`Map_state.t` goes in the snapshot** — it is small (a handful of
  features) and is exactly "the current truth of bridges/gates/caves".
- **`Game_map.t` should NOT ride in every snapshot** — the grids are tens
  of thousands of cells; at 30 Hz that is megabytes/sec of unchanged
  bytes. Fetch it **once at join** (e.g. the `join_game_rpc` response, or
  a `get_map_rpc`), then send only `Map_state.t` per tick.

`Map_state.Update.t` exists for the server game loop (react to "what just
changed") and keeps a delta-based feed possible later
(`apply_update`-folding provably reproduces the state); the current
full-snapshot protocol simply doesn't need deltas on the wire.

## Geometry: grid world, free cars

Terrain is a rectangular cell grid — every map query is an O(1) array
lookup, no geometry math. Cars keep continuous positions/headings, so
driving still feels smooth; physics samples `surface_at`/`is_blocked` at
the car's next position (center + a corner or two) and rejects/slides on
solid cells.

Conventions (pinned in the `.mli`s):

- **y-up, origin bottom-left, `row 0` = bottom row** — exactly the OCaml
  `Graphics` window frame, so the client never flips an axis.
- `cell_size` converts `Vec2.t` world units to `Cell.t` grid coordinates
  (default 1.0 world unit per cell).
- Out-of-grid cells read `Wall` (total queries — no edge special-casing).
- **Anti-tunneling**: at 30 Hz, cap car speed so no car moves more than
  ~1 cell per tick (or sample the segment), or a fast car can pass
  through a 1-cell wall between samples. Author lanes ≥ 3–4 cells wide so
  the grid never fights the steering.

## Components and state machines

Static: surface grid, environment grid, checkpoints (ordered strips;
checkpoint 0 = start/finish; each carries a respawn `Pose.t`), start grid
(`Pose.t` list). Branch routes are *drawn*, not modeled — progress only
counts the next expected checkpoint, so forks that split and re-merge
between consecutive checkpoints just work, and shortcuts earn nothing.

Dynamic features (all transitions server-side; every hostile action has a
**telegraph phase** — the co-pilot's warning window):

```
Bridge      Intact --collapse--> Collapsing(falls_at)   ~1s, still drivable
            Collapsing --tick--> Collapsed(rebuilt_at)  cells become a GAP
            Collapsed  --tick--> Intact                 auto-rebuilds

Gate        Open --close--> Closing(shut_at)            ~1.5s, still passable
            Closing --tick--> Closed(reopens_at)        cells read Wall
            Closed  --tick--> Open

Stalactite  Hanging --trigger--> Falling(lands_at)      ~0.8s, dust + shadow
            Falling --tick--> Debris(cleared_at)        impact: game loop stuns
            Debris  --tick--> Hanging                   cars in cells; then solid
                                                        rubble until cleared

Ice patch   (Place_ice) --> { melts_at }                spawned on open road
            melts_at reached, or flame counter --> Removed
```

Everything auto-restores, so no combination of sabotage can permanently
break a lap (validation enforces the rest — see below).

### Facts, not consequences

The map answers *what is here*; physics owns *what happens*:

- `Map_state.surface_at` — base grid + overlays (`Closed` gate and
  `Debris` read `Wall`; telegraph phases stay drivable).
- `Map_state.is_gap` — true on a `Collapsed` bridge's cells. The map
  reports the hole; physics decides who falls (gliding cars cross).
- `Map_state.traction_at` — product of feature grip multipliers (ice).
- `Environment.is_dark` — `Cave`; the client combines it with the car's
  flashlight state.

The map never consults car state (gliders, flashlights, items).

## Map file format (pure sexp)

One sexp file per track. Grids are lists of rows written **top row
first** (as a human reads them); `Game_map.load` flips into the internal
row-0-=-bottom arrays. Features are authored as kind + footprint — no
ids (assigned by `load` in listing order) and no phases (everything
starts at rest: `Intact`/`Open`/`Hanging`).

```lisp
((name castle-run)
 (laps_to_win 3)
 (cell_size 1.0)
 (surfaces
  ((Wall Wall Wall Wall Wall Wall Wall Wall)
   (Wall Road Road Road Road Road Road Wall)
   (Wall Road Wall Wall Wall Wall Road Wall)
   (Wall Road Road Road Road Road Road Wall)
   (Wall Wall Wall Wall Wall Wall Wall Wall)))
 (environments
  ((Castle Castle Castle Castle Castle Castle Cave Cave)
   (Castle Castle Castle Castle Castle Castle Cave Cave)
   (Forest Forest Forest Forest Castle Castle Cave Cave)
   (Forest Forest Forest Forest Castle Castle Cave Cave)
   (Forest Forest Forest Forest Castle Castle Cave Cave)))
 (checkpoints
  (((index 0)
    (cells (((col 2) (row 3))))
    (respawn ((pos ((x 2.5) (y 3.5))) (heading 0))))
   ((index 1)
    (cells (((col 5) (row 1))))
    (respawn ((pos ((x 5.5) (y 1.5))) (heading 3.14159))))))
 (start_grid
  (((pos ((x 1.5) (y 3.5))) (heading 0))
   ((pos ((x 1.5) (y 1.5))) (heading 0))))
 (features
  (((kind Bridge) (cells (((col 3) (row 1)) ((col 4) (row 1)))))
   ((kind Gate) (cells (((col 6) (row 3))))))))
```

(Illustrative, hand-typed — don't trust it as a validated map. The real,
validated example is **`maps/castle_run.sexp`**: a 26×15 counterclockwise
circuit — start/finish in the castle's right corridor, a gorge bridge in
the top corridor with a one-cell ledge detour, a forked forest descent
with a gate on the inner lane, and a cave corridor with a stalactite that
always leaves one lane open. `lib/map/test/test_game_map.ml` loads and
summarizes it in expect tests.)

Yes, drawing a big grid in sexp atoms is clunky; the upside is the parser
is `[@@deriving of_sexp]` on an internal `Spec` type plus validation, with
zero hand-rolled parsing. If authoring hurts, an ASCII front-end (chars →
constructors) can be added later *behind the same `load : Sexp.t -> t
Or_error.t`* without changing any interface. A map generator script is
another option.

`load` validation (map files are human-authored — check everything,
collect **all** errors, not just the first):

- grids rectangular, nonempty, same dimensions;
- checkpoint indexes exactly `0..n-1`, `n >= 2`, cells on `Road`;
- each checkpoint BFS-reachable from the previous (and checkpoint 1 from
  every start slot) over non-solid cells **with every gate closed, every
  bridge collapsed, and every stalactite fallen simultaneously** — the
  strictest single check, and it makes "sabotage can never brick the
  lap" true forever;
- start slots on `Road`;
- feature footprints nonempty, non-overlapping, on `Road`; stalactites
  only over `Cave` cells; ice patches cannot be authored (they are
  spawned in play only).

## Module map

Dependency layers (each depends only on layers above):

```
racing_types: Position, Tick                    (the shared vocabulary)
surface   environment   feature_id              (leaves)
pose ── cell                                    (position)
feature (tick cell surface feature_id)
checkpoint (cell pose)        track_action (feature_id position)
game_map (everything above)
map_state (game_map + everything; Update + Viewport submodules)
racing_map (re-exports the lot; `open Racing_map` where convenient)
```

Implementation status: **everything is implemented** — the former stubs
(`Game_map.load` + validation, `Checkpoint.Progress.on_touch`, all of
`Map_state`'s transitions and composed queries, `viewport`) are real and
covered by the expect tests in `lib/map/test/`. Gameplay tuning constants
(telegraph/outage/melt durations at 30 ticks/s, ice radius) sit at the
top of `map_state.ml`, marked provisional until a config module exists.

## Rendering notes (OCaml `graphics`)

- The library exposes render-ready **data**; all drawing lives in the
  client. `Map_state.viewport` returns the driver's slice: composed
  surface/environment arrays + visible features + `is_dark`.
- Budget: a driver viewport of ~30×20 cells is ~600 `fill_rect`s per
  frame — comfortable with `auto_synchronize false` and one
  `synchronize ()` per frame (the standard double-buffering pattern).
- The co-pilot's whole-map view should **not** redraw ~30k cells per
  frame: pre-render the static base map into a `Graphics.image` once,
  blit it each frame, and draw only dynamic features and cars on top.
- Darkness: if the viewport `is_dark` and the car has no lit flashlight,
  draw black except a radius around the car. Telegraphs animate
  client-side from `phase` + `expiry - now` (the snapshot carries the
  current tick).

## Test plan (implemented in `lib/map/test/` — test_checkpoint,
test_game_map, test_map_state)

- `Progress.on_touch`: a table-style expect test walking a 3-checkpoint
  lap — advance, ignore wrong/backwards touches, complete a lap.
- `Game_map.load`: one good map (print the loaded summary) and one golden
  bad map per validation rule (snapshot the error messages — they should
  name the offending cell/index).
- Action matrix: apply each `Track_action.t` to each feature kind in each
  phase; snapshot the accept/reject table.
- Replication property: for a scripted action/tick sequence, folding the
  emitted updates with `apply_update` into a copy `Map_state.equal`s the
  server's state.
- `viewport`: tiny map, print the composed surface grid before/after a
  gate closes.
- Drift guards: print `Feature.Kind.all` and `Surface.all` /
  `Environment.all` so additions show up in review.

## Open questions (suggested defaults in parentheses)

1. Durations: telegraph lengths, outage lengths, ice melt (bridge ~1s
   telegraph / ~10s out; gate ~1.5s / ~8s; stalactite ~0.8s / ~5s debris;
   ice ~8s — all at 30 ticks/s, as constants in `map_state.ml` until a
   config module exists).
2. Track-player ability economy: per-ability cooldowns vs. shared
   resource (per-ability cooldowns — zero extra map work).
3. Ice placement: anywhere on open road within some radius vs. authored
   anchor points (anywhere on `Road`; server validates via `surface_at`).
4. Ice patch footprint radius (~1.5 cells via `Cell.in_radius`).
5. Tick rate (30/s) and map scale (cell_size 1.0, maps ~100–200 cells per
   side, lanes ≥ 4 wide, car speed capped at ≤ 1 cell/tick).
6. Falling through a gap: respawn delay (~3s) at the last-touched
   checkpoint's `respawn` pose — car-side logic, the map just supplies
   the pose.
7. Stalactite impact on cars: stun (~2s) vs. damage (stun).
8. Co-pilot's view: whole map vs. enlarged window (whole map — seeing
   ahead is their job; use the base-map blit).
9. ~~Unify with `Racing_types`~~ — **done** (PR #5): `racing_map` now
   uses `Racing_types.{Position,Tick}` and `Cell.of_position` bridges
   car space to the grid. Still open: `Racing_types.Interference`
   growing map-targeting constructors that embed `Track_action.t`.
10. Map delivery at join: `join_game_rpc` response vs. a dedicated
    `get_map_rpc` (dedicated RPC — reconnecting clients can refetch
    without rejoining).
