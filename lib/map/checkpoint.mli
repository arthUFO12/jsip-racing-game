(** An ordered strip of cells a car must cross; checkpoint [0] is the
    start/finish line. Only the NEXT expected checkpoint counts
    ({!Progress.on_touch}), which buys two things for free: forked routes
    need no special handling (branches split and re-merge between consecutive
    checkpoints), and cutting the course or driving backwards earns nothing.
    Each checkpoint also carries the {!Pose.t} where cars respawn after
    falling through a gap. *)

open! Core

type t =
  { index : int (** position in lap order; [0] is the start/finish line *)
  ; cells : Cell.t list (** a strip spanning the full track width *)
  ; respawn : Pose.t (** where a fallen car reappears, facing race-forward *)
  }
[@@deriving sexp, bin_io, compare, equal]

module Progress : sig
  (** One car's lap bookkeeping. It lives with the server's per-car records,
      but the logic is here so laps are testable without cars. *)
  type t =
    { next_index : int (** the checkpoint this car must touch next *)
    ; laps_completed : int
    }
  [@@deriving sexp, bin_io, compare, equal]

  (** Cars start on the line having already "crossed" checkpoint [0]:
      [next_index = 1], no laps completed. *)
  val initial : t

  (** Advance one car's progress, given that its cell sits inside checkpoint
      [touched] this tick (see {!Game_map.checkpoint_at}). Touching any
      checkpoint other than [next_index] is [`Ignored]; touching the expected
      checkpoint [0] closes the loop as [`Lap_completed]. The caller compares
      [laps_completed] against {!Game_map.laps_to_win}. *)
  val on_touch
    :  t
    -> checkpoint_count:int
    -> touched:int
    -> t * [ `Advanced | `Lap_completed | `Ignored ]
end
