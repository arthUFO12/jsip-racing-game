(** The domain vocabulary of the racing game: plain data shared by the
    server, both clients, and the protocol. No game logic lives here — just
    types and the smart constructors that keep bad values out ("make illegal
    states unrepresentable").

    A map of the library:

    - people: {!Player_id}, {!Player_name}, {!Player}, {!Role}, {!Team_id},
      {!Team}
    - motion: {!Position}, {!Heading}, {!Speed}, {!Velocity}, {!Driver_input}
    - items and sabotage: {!Powerup}, {!Interference}, {!Effect}
    - race bookkeeping: {!Tick}, {!Race_status}

    The RPCs that move these values are sketched in [doc/rpc-protocol.md]; a
    protocol library comes later. The track model is being designed
    separately, and brings the rest of the vocabulary with it when it lands:
    map-feature ids (bridges, gates, cave sections), the interference that
    targets them, and the per-driver race state ([Car.t]: position,
    condition, laps). *)

open! Core
module Driver_input = Driver_input
module Effect = Effect
module Heading = Heading
module Interference = Interference
module Player = Player
module Player_id = Player_id
module Player_name = Player_name
module Position = Position
module Powerup = Powerup
module Race_status = Race_status
module Role = Role
module Speed = Speed
module Team = Team
module Team_id = Team_id
module Tick = Tick
module Velocity = Velocity
