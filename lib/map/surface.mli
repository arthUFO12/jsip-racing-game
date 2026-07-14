(** What the ground is at one cell, AFTER dynamic feature overlays are
    applied: a closed castle gate and settled stalactite debris read as
    [Wall]; everything else shows the authored base grid. Ask
    {!Map_state.surface_at} for that composed answer;
    {!Game_map.base_surface_at} is the static layer underneath.

    The map states facts and physics owns consequences: nothing here knows
    about cars, gliders, or crashes. There is deliberately no slow or deadly
    ground in v1 — hazards are dynamic features ({!Feature}), not surfaces. *)

open! Core

type t =
  | Road (** drivable *)
  | Wall (** solid — castle stone, cave rock, and the map border *)
  | Trees
  (** solid — the forest's tree line; differs from [Wall] only in how the
      client draws it *)
[@@deriving sexp, bin_io, compare, equal, enumerate]

(** [Wall] and [Trees]. Physics rejects any move whose sampled cells are
    solid. *)
val is_solid : t -> bool
