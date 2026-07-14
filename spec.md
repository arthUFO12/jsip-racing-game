# One-day brainstorm — JSIP racing game

> **Naming note:** the code (`lib/types/player.mli`) calls the two roles
> `Driver` and `Copilot`. This doc now uses those names everywhere; earlier
> drafts mixed "driving player", "racing player", and "track player".
>
> Questions the team still needs to answer are marked **[OPEN]**.

## 1. Project overview

### A. What kind of racing game are you going to create? Provide the high-level description of the project and outline its major software components.

We are going to create a racing game where teams of two compete against one
another. One person (the **driver**) drives the vehicle; the other (the
**copilot**) is in charge of the track. Being in charge of the track
involves:

- sabotaging the other teams,
- changing the track to give their own driver an advantage, and
- seeing upcoming obstacles/parts of the track so they can warn their
  driver.

The driver can only see a small part of the track at one time, so they
depend on their copilot's warnings.

- **[OPEN]** How many teams race at once? Is there a minimum/maximum?
- **[OPEN]** What is the win condition — first team to finish N laps?

### B. Which specializations does your project cover?

- **Interactivity** — players interact with obstacles on the map, and
  interact and converse with other players.
- **Networking** — players connect to a central server through the
  client-side app.
- **[OPEN]** We also plan to render cars, obstacles, and car visual states
  (exploding, wings, …) — decide whether to claim **visual effects** as a
  third specialization.

## 2. Project components

### A. Which are the main parts of the project?

**Server-side app**

- Library for visual elements.
  - **[OPEN]** The client is in charge of rendering (see the protocol
    below), so what lives here? If this is the shared representation of
    track geometry and obstacles, rename it to say that.
- Library for collisions and player interactions.
- Server module for handling player connections and permissions.
- Modules for cars, obstacles, powerups, and maps.
- Module for running a game.

**Client-side app**

- Library for drawing cars, obstacles, powerups, etc. on the screen.
- Module for interference — the copilot's sabotage / track-editing
  controls.
- Module(s) for stats and player info (leaderboard, available inventory,
  etc.).
- Module for racing mode — the driver's view and controls.

**Protocol between the server and client applications**

- `Pipe_rpc`. The server owns all game logic and pushes state to clients
  on every update.
- Clients only send their inputs (heading, speed, powerup uses) and are in
  charge of rendering.

### B. Which parts of the project can be cut for time/interest if necessary?

- The number of interference strategies the copilot can invoke — ship a
  small core set first (e.g. one power-up/power-down pair) and add the
  rest if time allows.
- **[OPEN]** Worth listing more cut candidates now (leaderboard? multiple
  themes?) so the priority order is already decided when time gets tight.

### C. Which parts remain out of scope of this project?

- Racing different types of vehicles on different types of tracks (e.g.
  airplanes in the air).
- Voice connection between the two teammates, or other communication
  strategies.

### D. Which parts will have the most technical/software complexity/difficulty?

- **Multiplayer state.** All players are present on the same track, so
  there may be issues with race conditions or fairness — e.g. simultaneous
  inputs from different clients, or a track change landing while a car is
  in the affected section.
- **Per-role views.** Generating different views of the same game state
  depending on whether a player is a copilot or a driver.

## 3. Power-ups and power-downs

Most power-downs are paired with a counter power-up. A counter has to be
deployed by the team's own copilot *in time* — reacting quickly is part of
the gameplay.

| Power-down (sabotage other teams)                                | Counter power-up (protect your own driver) |
| ---------------------------------------------------------------- | ------------------------------------------ |
| Break a bridge — cars fall into the water/void                   | Glider — glide over drops in the track     |
| Ice — track very slippery for all drivers; melts after X seconds | Flame magic — melts the ice                |
| Stalactites triggered to fall (cave sections only)               | Flashlights — light up cave sections       |
| Vines across the track — reduce speed by X% for X seconds        | Axe — cut through the vines                |
| Mud bomb — blocks one driver's visibility for X seconds          | *(none yet — intended?)*                   |
| Closing castle gates — forces a driver onto a different route    | *(none — the driver just reroutes)*        |

Standalone power-ups (no power-down attached):

- Speed boost.
- Invincibility — unaffected by individual power-downs.

Power-downs come in two kinds:

- **Track power-downs** affect a section of track for every driver: broken
  bridges, ice, castle gates, stalactites. The server tracks their state
  and timers.
- **Individual power-downs** target one driver: vines, mud bombs.

Open questions:

- **[OPEN]** Replace the X placeholders with real numbers (or decide they
  are per-map configuration).
- **[OPEN]** How does a copilot acquire inventory — a fixed loadout at
  race start, earned over time, or something else?
- **[OPEN]** Does invincibility also protect against *track* power-downs
  (does an invincible car survive a broken bridge)?

## 4. Things we still have to think about

- Switching roles (mid-game? between races?).
- Theme — forest, castle, Game of Thrones vibe.

## 5. State of the game

- Tag every update (input and output) with a globally unique player ID.
- One pipe. **[OPEN]** One pipe *per client*, or literally one shared
  pipe? (Presumably one per client via `Pipe_rpc` — say so explicitly.)

### Server (owns all game logic)

Keeps track of:

- the list of all players and their details (names, copilot or driver,
  number of laps, etc.);
- where all players are on the map, and their velocities;
- the state of track power-downs (e.g. whether bridge #1 is collapsed),
  including timers on how long each power-down lasts.

### Copilot (client)

- **Keeps track of:** the list of all players and their details; how much
  inventory they have.
- **Sends:** uses of power-ups / power-downs.
- **Receives:** updated effects from uses of power-ups / power-downs.
- **[OPEN]** The copilot's whole job is watching the track ahead — don't
  they also need to receive every player's position and the track state,
  not just power-up/power-down effects?

### Driver (client)

- **Keeps track of:** the list of all players and their details.
- **Sends:** keyboard input (desired heading and velocity).
- **Receives:**
  - updated coordinates + velocity of their own car, including power-down
    effects (speed reduction, etc.);
  - the visual state of the car (exploding, with wings, etc.).
- **[OPEN]** To draw other cars in view, the driver also needs *other*
  players' coordinates — the list above only mentions their own.
