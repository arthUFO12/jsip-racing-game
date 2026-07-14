open! Core

(** The good items. A track player sends one to their own driver
    ([assist_teammate_rpc] in [doc/rpc-protocol.md]); on the driver it shows
    up as a timed {!Effect.t} in the next snapshot.

    The last four are counters, one per threat: [Glider] survives a collapsed
    bridge, [Flame_magic] melts the ice a track player pours on the track (a
    [Racing_map.Track_action.Place_ice] patch), [Flashlight] lights cave
    sections, [Axe] cuts {!Interference.Vines}.

    [Comparable.S] is included so inventories can be maps, e.g. counting what
    a track player holds:

    {[
      let count (inventory : int Powerup.Map.t) powerup =
        Map.find inventory powerup |> Option.value ~default:0
      ;;
    ]} *)

type t =
  | Speed_boost (** go faster for a while *)
  | Invincibility (** immune to individual powerdowns while active *)
  | Glider (** glide over drops where the track has collapsed *)
  | Flame_magic (** melts the ice a track player pours on the track *)
  | Flashlight (** see inside cave sections *)
  | Axe (** cut through {!Interference.Vines} *)
[@@deriving bin_io, enumerate, hash, sexp]

include Comparable.S with type t := t
