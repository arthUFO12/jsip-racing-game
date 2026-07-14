(** The game's colors, in one place. The art direction is the fantasy forest
    / castle / cave look of the reference mock ("Dragon's Breath Raceway"):
    warm dirt roads, lush tree lines, cool castle stone, near-black cave
    rock, blue water in the gaps, and glowing cyan ice crystals.

    {!ground} is the base fill of a cell, chosen from the two orthogonal
    facts the map exposes — what the ground {e is} ({!Racing_map.Surface})
    and which theme zone it sits in ({!Racing_map.Environment}). Everything
    else here is a named constant so tuning the look never means hunting for
    a magic [rgb] deep in the drawing code. *)

open! Core
open Racing_map
open Racing_types

(** Base fill for one terrain cell, before feature overlays and cave shading. *)
val ground : surface:Surface.t -> environment:Environment.t -> Prim.Color.t

(** A car's livery, cycled over a fixed vivid set (red, blue, gold, green,
    purple, orange) keyed by {!Team_id}. *)
val team : Team_id.t -> Prim.Color.t

(** {2 Feature colors} *)

(** a collapsed bridge: the gap *)
val water : Prim.Color.t

val water_highlight : Prim.Color.t
val bridge_plank : Prim.Color.t

(** a closed portcullis reads as wall *)
val gate_iron : Prim.Color.t

val gate_bar : Prim.Color.t
val stalactite : Prim.Color.t

(** settled rubble, also wall-like *)
val debris : Prim.Color.t

val ice : Prim.Color.t
val ice_shine : Prim.Color.t

(** {2 Status / warning colors} *)

(** amber "danger incoming" flash *)
val telegraph : Prim.Color.t

val danger : Prim.Color.t
val boost_flame : Prim.Color.t
val glider_wing : Prim.Color.t

(** invincibility shimmer *)
val shield : Prim.Color.t

val vines : Prim.Color.t

(** {2 Chrome} *)

(** the CRT frame around the play area *)
val bezel : Prim.Color.t

val car_shadow : Prim.Color.t
val cave_shade : Prim.Color.t
val hud_panel : Prim.Color.t
val hud_border : Prim.Color.t
val hud_text : Prim.Color.t
val hud_title : Prim.Color.t

(** the highlighted value, e.g. POS 1st *)
val hud_accent : Prim.Color.t
