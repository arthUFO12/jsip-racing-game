(** A racing-game track: the immutable layout ({!Game_map}), the live
    sabotage state ({!Map_state}), and the vocabulary types they share.
    Linked by both the server (authoritative state, physics fact queries)
    and the client (replica + rendering data). Depends on [core] only —
    rendering with the [graphics] library happens in the client apps,
    never here. *)

module Cell = Cell
module Checkpoint = Checkpoint
module Environment = Environment
module Feature = Feature
module Feature_id = Feature_id
module Game_map = Game_map
module Map_state = Map_state
module Pose = Pose
module Surface = Surface
module Tick = Tick
module Track_action = Track_action
module Vec2 = Vec2
