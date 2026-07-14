(** The network front door: owns the authoritative {!Game_state.t}, serves
    every RPC in {!Rpc_protocol}, and runs the tick loop that [step]s the
    world and pushes a {!Rpc_protocol.Game_snapshot.t} to every game-feed
    subscriber, {!Game_state.tick_duration} apart.

    Connections are the permission system: each TCP connection carries at
    most one joined player, and every command is attributed to the player who
    joined on that connection — payloads never say who is calling, so driving
    someone else's car is unrepresentable at the protocol level. What a
    player is {e allowed} to do (role checks, inventory, targets) is
    {!Game_state}'s job.

    Slow consumers are dropped-frame consumers: a subscriber that stops
    reading has new snapshots skipped, not queued, because each snapshot
    supersedes the last. (Contrast the unbounded
    [write_without_pushback_if_open] smell flagged in jsip-exchange's gateway
    — designed out here from the start.)

    Known limitation, deliberately: a player who disconnects stays in the
    game — their car just stops receiving input. Removing them cleanly
    collides with {!Racing_types.Team.t}'s two-player invariant, and mid-race
    "my partner dropped" rules are a design conversation for later. *)

open! Core
open! Async
open Racing_map

type t

(** Bind the port, start the tick loop, serve until the process dies. *)
val create : map:Game_map.t -> port:int -> t Deferred.t

(** The port actually bound — useful when [port] was [0] ("any free port"),
    e.g. in tests. *)
val port : t -> int
