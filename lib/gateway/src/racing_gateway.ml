(** The server side of the racing game's networking, and the protocol both
    sides share:

    - {!Rpc_protocol} — the wire vocabulary: every RPC, plus the protocol
      types ([Join_request], [Game_snapshot], [Sabotage], ...). Clients
      should depend on this and nothing else here.
    - {!Game_state} — the authoritative world: players, teams, cars,
      inventories, effects, the live track, the race lifecycle.
    - {!Physics} — how driver intent becomes motion, one tick at a time.
    - {!Server} — the RPC server and tick loop tying it all together.

    The domain vocabulary comes from {!Racing_types}; the track comes from
    {!Racing_map}. *)

open! Core
module Game_state = Game_state
module Physics = Physics
module Rpc_protocol = Rpc_protocol
module Server = Server
