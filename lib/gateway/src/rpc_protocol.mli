(** RPC definitions for client-server communication — the wire protocol of
    the racing game.

    The server owns all game state, authoritatively. Clients send intents
    (join, drive, use items) and subscribe to {!game_feed_rpc}, which pushes
    one complete {!Game_snapshot.t} per tick — the whole state every time,
    not a delta. Clients hold no state of their own: they render the latest
    snapshot, and a dropped message costs nothing because the next snapshot
    supersedes it.

    Sessions replace explicit identity: no RPC below carries the {e sender's}
    {!Player_id.t}. The server remembers which player joined on which
    connection, so one client cannot drive another team's car. Only
    {e victims} of targeted interference travel as [Player_id.t] payloads.

    A trust note on [bin_io]: decoding skips smart constructors, so
    everything a client can send is either unvalidatable-by-construction
    (four booleans, bare variants) or re-checked by the server ([name] below
    goes through {!Player_name.of_string}; interference targets are validated
    before they apply). Server-to-client data is trusted — the server built
    it. *)

open! Core
open Racing_types
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

module Car : sig
  (** Where one driver's car is and how it is moving — the per-driver motion
      state pushed in every snapshot. This will grow (laps, visual condition,
      ...) when the track model lands; keep any new field server-computed
      machine data, like these. *)
  type t =
    { position : Position.t
    ; velocity : Velocity.t
    }
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Game_snapshot : sig
  (** One complete statement of the world, pushed to every client every tick.
      There is no [track] field yet — the track model is being designed
      separately; it slots in here when it exists. *)
  type t =
    { tick : Tick.t (** monotonic; clients render the newest, drop stale *)
    ; race_status : Race_status.t
    ; teams : Team.t list (** who is playing; roles are the team's slots *)
    ; cars : Car.t Player_id.Map.t (** keyed by driver *)
    ; effects : Effect.t list Player_id.Map.t
    (** active power(up|down)s per driver, with remaining time *)
    ; inventories : Powerup.t list Player_id.Map.t
    (** held items: a track player's stock to grant, a driver's to use *)
    }
  [@@deriving bin_io, sexp_of]
end

module Interference : sig
  (** A track player's sabotage, unified across the two libraries that own
      its halves: {!Racing_types.Interference} (powerdowns aimed at a rival
      driver — vines, mud) and {!Racing_map.Track_action} (actions that alter
      the track — collapse a bridge, close a gate, drop a stalactite, pour
      ice). Neither library can reference the other, so the protocol unions
      them here rather than duplicating a single constructor of either. *)
  type t =
    | On_driver of Racing_types.Interference.t
    | On_track of Racing_map.Track_action.t
  [@@deriving bin_io, compare, equal, sexp_of]
end

(** Join as a named player on a team, as [Driver] or [Track_player]. Returns
    the server-assigned {!Player_id.t} that identifies this player in every
    snapshot. Errors: invalid name, seat already taken, or this connection
    already joined. *)
val join_game_rpc : (Join_request.t, Player_id.t Or_error.t) Rpc.Rpc.t

(** THE feed: one complete {!Game_snapshot.t} per tick. Confirmation of any
    input is the next snapshot, never a response value — state flows one way,
    out of this pipe. *)
val game_feed_rpc : (unit, Game_snapshot.t, Error.t) Rpc.Pipe_rpc.t

(** Driver key state, sent whenever it changes. Pure intent — the server
    integrates it through physics and active powerdowns; the result appears
    in the next snapshot as this car's {!Velocity.t}. One-way because at
    input rates there is nothing useful to do with a per-message response. *)
val driver_input_rpc : Driver_input.t Rpc.One_way.t

(** Driver uses a powerup they hold. Errors: not in inventory, not a driver,
    race not running. *)
val use_powerup_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t

(** Track player invokes interference against other teams — an
    {!Interference.t}, so one RPC carries both driver-targeting powerdowns
    and track-altering actions. Errors: not a track player, invalid target (a
    track player, or your own driver), race not running. *)
val use_interference_rpc : (Interference.t, unit Or_error.t) Rpc.Rpc.t

(** Track player grants a powerup from their stock to their own driver, who
    can then {!use_powerup_rpc} it at the right moment. Errors: not in stock,
    not a track player. *)
val assist_teammate_rpc : (Powerup.t, unit Or_error.t) Rpc.Rpc.t
