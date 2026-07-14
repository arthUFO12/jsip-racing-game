(** A richer sprite kit for the driver view, plus a whole-track minimap.

    These are the detailed cousins of {!Jsip_client_render.Render}'s light
    tile/car art: where {!Jsip_client_render.Render.tile_texture} draws a
    flat green square for a tree cell, {!tree_cluster} here draws a trunk and
    layered foliage. Every function is PURE — it takes a pixel box (y-up,
    origin bottom-left, matching {!Jsip_client_render.Prim}) and returns the
    {!Jsip_client_render.Prim.t} geometry to draw there, so the whole kit is
    expect-testable without ever opening a window. The integrator wires these
    fragments into the driver's scene later; nothing here decides layout or
    which cell gets which sprite.

    Everything is primitive-only and cheap (a handful of shapes each). Extra
    tints beyond {!Jsip_client_render.Palette} are kept as local constants —
    this module never edits the shared palette. *)

open! Core
open Racing_map
open Racing_types
module Prim = Jsip_client_render.Prim

(** Layered foliage filling the cell box — richer than a flat green tile. A
    trunk plus overlapping foliage discs in lightened/darkened shades of
    [base] (the cell's tree-line green from
    {!Jsip_client_render.Palette.ground}). *)
val tree_cluster
  :  x:int
  -> y:int
  -> size:int
  -> base:Prim.Color.t
  -> Prim.t list

(** Offset brick courses over [base]: staggered mortar seams in a darker
    [base], for castle [Wall] cells. *)
val brick_wall
  :  x:int
  -> y:int
  -> size:int
  -> base:Prim.Color.t
  -> Prim.t list

(** Angular rock facets and speckle over [base], for forest/cave [Wall]
    cells. *)
val rock_wall
  :  x:int
  -> y:int
  -> size:int
  -> base:Prim.Color.t
  -> Prim.t list

(** Wood planks with horizontal seams and short grain ticks over [base] — a
    castle-interior floor. *)
val plank_floor
  :  x:int
  -> y:int
  -> size:int
  -> base:Prim.Color.t
  -> Prim.t list

(** A detailed top-down car centered on [(cx, cy)]: shadow, rotated body,
    windshield, four wheels, headlights, and an optional racing [number].
    [heading] is radians CCW from +x (0 points right), so the sprite visibly
    turns as [heading] changes. [livery] is the body color (usually
    {!Jsip_client_render.Palette.team}). *)
val car_sprite
  :  cx:int
  -> cy:int
  -> size:int
  -> heading:float
  -> livery:Prim.Color.t
  -> number:int option
  -> Prim.t list

(** A castle banner on a pole (a decorative prop for castle cells): pole,
    swallowtail flag in [color], a darker trim line, and a small pennant. *)
val banner : x:int -> y:int -> size:int -> color:Prim.Color.t -> Prim.t list

(** A glowing rune-crystal cluster, matching the ice-crystal look
    ({!Jsip_client_render.Palette.ice} / [ice_shine]): a soft glow disc
    behind two or three cyan diamonds with white shine ticks. *)
val rune_crystal : x:int -> y:int -> size:int -> Prim.t list

module Minimap : sig
  (** A whole-track inset fit into the pixel box [(x, y, w, h)]: one composed
      terrain square per cell (surface + environment through
      {!Jsip_client_render.Palette.ground}), a colored dot per car, and a
      thin border. The grid is squared to the largest integer cell size that
      fits and centered in the box (letterboxed, never stretched). *)
  val render
    :  Game_map.t
    -> Map_state.t
    -> cars:(Position.t * Team_id.t) list
    -> x:int
    -> y:int
    -> w:int
    -> h:int
    -> Prim.t list
end
