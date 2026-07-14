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

The first team whose driver crosses the finish line wins. A race supports
up to 7 teams, no more.

### B. Which specializations does your project cover?

- **Interactivity** — players interact with obstacles on the map, and
  interact and converse with other players.
- **Networking** — players connect to a central server through the
  client-side app.
- **Visual effects** — drawing cars, obstacles, powerups, and car visual
  states (exploding, wings, …) on the client.

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
- One broadcast feed shared by all clients: every client receives the
  same full game state on every update, tagged with globally unique
  player IDs. Each client filters and renders the view for its role.
  (With `Pipe_rpc`, each subscriber technically holds its own pipe, but
  the content is identical for everyone.)
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
- **Per-role views.** All clients receive the same game state, so the
  copilot and driver clients must render very different views of it
  (whole-track overview vs. the driver's small window).

## 3. Power-ups and power-downs

Most power-downs are paired with a counter power-up. A counter has to be
deployed by the team's own copilot *in time* — reacting quickly is part of
the gameplay.

| Power-down (sabotage other teams)                                | Counter power-up (protect your own driver) |
| ---------------------------------------------------------------- | ------------------------------------------ |
| Break a bridge — cars fall into the water/void                   | Glider — glide over drops in the track     |
| Ice — track very slippery for all drivers; melts after 10 seconds | Flame magic — melts the ice              |
| Stalactites triggered to fall (cave sections only)               | Flashlights — light up cave sections       |
| Vines across the track — reduce speed by 50% for 8 seconds       | Axe — cut through the vines                |
| Mud bomb — blocks one driver's visibility for 5 seconds          | *(none yet — intended?)*                   |
| Closing castle gates — forces a driver onto a different route    | *(none — the driver just reroutes)*        |

The durations above are initial values — name them as constants in the
code and tune them during playtesting.

Standalone power-ups (no power-down attached):

- Speed boost.
- Invincibility — unaffected by *individual* power-downs. Track
  power-downs still apply: an invincible car does not survive a broken
  bridge.

Power-downs come in two kinds:

- **Track power-downs** affect a section of track for every driver: broken
  bridges, ice, castle gates, stalactites. The server tracks their state
  and timers.
- **Individual power-downs** target one driver: vines, mud bombs.

Copilots earn inventory passively over time during the race (exact earn
rate TBD — tune during playtesting).

## 4. Things we still have to think about

- Switching roles (mid-game? between races?).
- Theme — forest, castle, Game of Thrones vibe.

## 5. State of the game

- Tag every update (input and output) with a globally unique player ID.
- One broadcast feed for all clients: everyone receives the full game
  state on every update, and each client filters it by role and player ID.
  (Consequence: the driver's limited view of the track is enforced by the
  driver client's renderer, not by the server sending less.)

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
- **Receives:** the full game state broadcast — every player's position
  and velocity, the state of track power-downs, and updated effects from
  uses of power-ups / power-downs. The copilot renders the whole-track
  view from it.

### Driver (client)

- **Keeps track of:** the list of all players and their details.
- **Sends:** keyboard input (desired heading and velocity).
- **Receives:** the same full game state broadcast as the copilot. The
  driver client filters it down to its small window of the track and
  renders:
  - its own car's updated coordinates + velocity, including power-down
    effects (speed reduction, etc.);
  - other cars currently in view;
  - the visual state of cars (exploding, with wings, etc.).
