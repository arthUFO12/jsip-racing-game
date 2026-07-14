# Running the server

> The entry point is `app/server/bin/main.ml` and the server itself is
> `lib/gateway/src/server.ml` — **the code is ground truth**; this doc is
> the tour.

## The command

From the repository root:

```sh
dune exec app/server/bin/main.exe -- -port 12345 -map maps/castle_run.sexp
```

which answers:

```
racing-game server: map castle-run, listening on port 12345
```

(`dune exec` compiles what it needs first, so a separate `dune build` is
not required — though running one is a fast way to see errors on their
own.)

Everything after `--` belongs to the server; before it, to dune. Both
flags are required:

| Flag | Meaning |
|---|---|
| `-port PORT` | TCP port to listen on. `0` means "any free port" — the startup line prints the one actually bound. |
| `-map FILE` | The track layout, a sexp file. `maps/castle_run.sexp` is the worked example; the schema is in `doc/map-design.md`. |

`-help` prints the same, straight from the source:

```sh
dune exec app/server/bin/main.exe -- -help
```

## What happens at startup

1. `Racing_map.Game_map.load_file_exn` reads and **validates** the map —
   human-authored files are checked exhaustively (grid shapes, checkpoint
   reachability under worst-case sabotage, feature footprints), and rule
   violations are reported all at once, not just the first.
2. The server binds the port and starts the tick loop: 30 ticks per
   second (`Game_state.ticks_per_second`), each tick stepping the world
   and pushing a full `Game_snapshot.t` to every game-feed subscriber.
3. It prints the one startup line and runs until killed (Ctrl-C).

There is no daemon mode and no config file — one process, one map, one
race. Restarting the process is how you reset the game.

## Connecting to it

Clients speak the protocol in `lib/gateway/src/rpc_protocol.mli`
(explained in `doc/rpc-protocol.md`): `join_game_rpc` to take a seat,
`game_feed_rpc` for the per-tick world, `driver_input_rpc` /
`use_powerup_rpc` / `use_interference_rpc` / `assist_teammate_rpc` to
act. Anyone may subscribe to the feed without joining — that is how a
monitor or spectator tool would watch a race.

A race needs at least one complete team: the first driver +
track-player pair on the same team id starts the countdown
(3 seconds — `countdown_seconds` in `lib/gateway/src/game_state.ml`).

## Troubleshooting

- **`Of_sexp_error ... missing fields`** at startup — the map file is not
  shaped like the schema at all (it failed to parse, before validation).
  Compare against `maps/castle_run.sexp`.
- **A list of validation errors** at startup — the sexp parsed but breaks
  the rules (checkpoint off-road, unreachable lap, overlapping features).
  Every violation is listed; fix them all in one pass.
- **Address already in use** — another process (probably an older server)
  holds the port. Pick another port or kill the old process.
- **No output when piping** — the startup line can lag behind a pipe's
  buffering; it appears promptly on a terminal or when redirected to a
  file.
- The server never prints per-tick output. If you want to watch the
  world, subscribe to `game_feed_rpc` — the snapshots are the log.
