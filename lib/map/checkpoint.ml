open! Core

type t =
  { index : int
  ; cells : Cell.t list
  ; respawn : Pose.t
  }
[@@deriving sexp, bin_io, compare, equal]

module Progress = struct
  type t =
    { next_index : int
    ; laps_completed : int
    }
  [@@deriving sexp, bin_io, compare, equal]

  let initial = { next_index = 1; laps_completed = 0 }

  (* Expected behavior:
     - [touched <> next_index]: [`Ignored] — a shortcut past the wrong
       checkpoint, driving backwards, or re-touching one already counted.
     - [touched = next_index = 0]: the car closed a loop:
       [laps_completed + 1], [next_index] becomes [1], [`Lap_completed].
     - [touched = next_index <> 0]: [next_index + 1] wrapping to [0] after
       [checkpoint_count - 1], [`Advanced]. *)
  let on_touch t ~checkpoint_count ~touched =
    match touched = t.next_index with
    | false -> t, `Ignored
    | true ->
      (match t.next_index with
       | 0 ->
         ( { next_index = 1; laps_completed = t.laps_completed + 1 }
         , `Lap_completed )
       | _ ->
         ( { t with next_index = (t.next_index + 1) mod checkpoint_count }
         , `Advanced ))
  ;;
end
