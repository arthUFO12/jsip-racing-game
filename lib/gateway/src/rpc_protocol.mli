(** RPC definitions for client-server communication — the wire protocol of
    the racing game.

    The server owns all game state, authoritatively. Clients send intents
    (join, drive, use items) and subscribe to {!game_feed_rpc}, which pushes
    one complete {!Game_snapshot.t} per tick — the whole mutable state every
    time, not a delta. Clients hold no state of their own: they render the
    latest snapshot, and a dropped message costs nothing because the next
    snapshot supersedes it. The one immutable exception is the track layout:
    {!Racing_map.Game_map.t} is big and never changes, so it arrives once in
    the {!Joined.t} response instead of riding in every snapshot (see
    "Protocol fit" in [doc/map-design.md]).

    Sessions replace explicit identity: no RPC below carries the {e sender's}
    {!Player_id.t}. The server remembers which player joined on which
    connection, so one client cannot drive another team's car. Only
    {e victims} of targeted interference travel as [Player_id.t] payloads.

    A trust note on [bin_io]: decoding skips smart constructors, so
    everything a client can send is either unvalidatable-by-construction
    (four booleans, bare variants) or re-checked by the server ([name] below
    goes through {!Player_name.of_string}; sabotage targets are validated
    before they apply). Server-to-client data is trusted — the server built
    it. *)

open! Core
open Racing_types
open Racing_map
module Rpc := Async_rpc_kernel.Rpc

module Join_request : sig
  (** What a client sends to enter the game: the name the human typed
      (validated server-side), which team to join, and which seat to take.
      Teammates agree on a shared team number out of band ("we're team 3");
      the server builds the {!Team.t} once both seats are filled. *)
  type t =
    { name : string (** validated with {!Player_name.of_string} on arrival *)
    ; team : Team_id.t
    ; role : Role.t
    }
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Joined : sig
  (** A successful join: who you are now, and the immutable track. Keep the
      map — it is not in snapshots. *)
  type t =
    { player_id : Player_id.t
    ; map : Game_map.t
    }
  [@@deriving bin_io, sexp_of]
end

module Player_info : sig
  (** One player and where they sit — every joined player appears in every
      snapshot with one of these, including players still waiting for a
      teammate (their team has no {!Team.t} yet). *)
  type t =
    { player : Player.t
    ; team : Team_id.t
    ; role : Role.t
    }
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Sabotage : sig
  (** Everything a track player can invoke, unified for one RPC. The two
      halves live in different libraries on purpose: car-targeted status
      effects are {!Interference.t} (domain vocabulary), map-targeted actions
      are {!Track_action.t} (validated against feature ids and phases by
      {!Map_state.apply_action}). This protocol type is where they meet — see
      the note in [lib/map/track_action.mli]. *)
  type t =
    | Car of Interference.t (** vines or mud bomb on a rival driver *)
    | Track of Track_action.t
    (** collapse a bridge, close a gate, drop stalactites, pour ice *)
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Car : sig
  (** One driver's car as of this tick: where it is, how it is moving, and
      how far through the race it is. All server-computed machine data. *)
  type t =
    { position : Position.t
    ; velocity : Velocity.t
    ; progress : Checkpoint.Progress.t (** laps and next checkpoint *)
    }
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Game_snapshot : sig
  (** One complete statement of the mutable world, pushed to every client
      every tick. Pair it with the {!Joined.t} map to render everything. *)
  type t =
    { tick : Tick.t (** monotonic; clients render the newest, drop stale *)
    ; race_status : Race_status.t
    ; players : Player_info.t list (** everyone, in join order *)
    ; teams : Team.t list (** completed pairs only *)
    ; cars : Car.t Player_id.Map.t (** keyed by driver *)
    ; track : Map_state.t (** live bridges/gates/stalactites/ice *)
    ; effects : Effect.t list Player_id.Map.t
    (** active power(up|down)s per driver, with remaining time *)
    ; inventories : Powerup.t list Player_id.Map.t
    (** held items: a track player's stock to grant, a driver's to use *)
    }
  [@@deriving bin_io, sexp_of]
end

(** Join as a named player on a team, as [Driver] or [Track_player]. Errors:
    invalid name, seat already taken, or this connection already joined. *)
val join_game_rpc : (Join_request.t, Joined.t Or_error.t) Rpc.Rpc.t

(** THE feed: one complete {!Game_snapshot.t} per tick. Confirmation of any
    input is the next snapshot, never a response value — state flows one way,
    out of this pipe. *)
val game_feed_rpc : (unit, Game_snapshot.t, Error.t) Rpc.Pipe_rpc.t

(** Driver key state, sent whenever it changes. Pure intent — the server
    integrates it through physics, terrain and active powerdowns; the result
    appears in the next snapshot as this car's {!Velocity.t}. One-way because
    at input rates there is nothing useful to do with a per-message response. *)
val driver_input_rpc : Driver_input.t Rpc.One_way.t

(** Driver uses a powerup they hold. Errors: not in inventory, not a driver,
    race not running, or (for {!Powerup.Flame_magic}) no ice nearby. *)
val use_powerup_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t

(** Track player invokes sabotage. Errors: not a track player, race not
    running, invalid car target (a track player, or your own driver), or
    whatever {!Map_state.apply_action} rejects (unknown feature, wrong kind,
    not in its rest phase, ice off the road). *)
val use_interference_rpc : (Sabotage.t, unit Or_error.t) Rpc.Rpc.t

(** Track player grants a powerup from their stock to their own driver, who
    can then {!use_powerup_rpc} it at the right moment. Errors: not in stock,
    not a track player, driver hasn't joined yet. *)
val assist_teammate_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t
