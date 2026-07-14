(** A track player's map-affecting sabotage, as {!Map_state.apply_action}
    validates it. The protocol's [Interference.t] (see [doc/rpc-protocol.md])
    should embed a [t] for its map-targeting cases; powerdowns that target
    one CAR rather than the track (vines, mud bombs) are car status effects
    and live with the car/game logic, not the map. *)

open! Core
open Racing_types

type t =
  | Collapse_bridge of Feature_id.t
  | Close_gate of Feature_id.t
  | Drop_stalactite of Feature_id.t
  | Place_ice of Position.t
  (** spawns a fresh {!Feature.Ice_patch} centered here; the server validates
      that the footprint lands on open road *)
[@@deriving sexp, bin_io, compare, equal]
