(** The driver's-eye screen: a close-up, car-centered slice of the track drawn
    in the fantasy look of {!Palette}, with a warm HUD bar across the top.

    The design is deliberately split so most of it is pure and testable:

    - {!scene_of_frame} turns a {!Frame.t} (a viewport plus the cars and HUD
      facts) into a flat {!Prim.t} [list] — no side effects, no window, so a
      whole frame's geometry is expect-testable and the same scene can be
      replayed by any backend.
    - {!open_window} / {!draw_frame} are the only impure part: they push that
      scene to an OCaml [Graphics] window.

    Cars arrive as {!Car.t}, a {e render-side} view (position, facing, team,
    active effects) rather than a shared domain [Car.t] — the track model
    hasn't defined one yet, and rendering shouldn't be what forces its
    shape. *)

open! Core
open Racing_map
open Racing_types

module Car : sig
  (** One car to draw. [effects] drives the state overlays (a boost flame, a
      glider's wings, an invincibility shimmer); [is_self] gets the local
      driver's car its "you" marker. *)
  type t =
    { pos : Position.t
    ; heading : Heading.t
    ; team : Team_id.t
    ; is_self : bool
    ; effects : Effect.t list
    }
end

module Frame : sig
  (** Everything one frame needs. [viewport] is the terrain slice
      ({!Racing_map.Map_state.viewport}); [cars] are the visible cars in world
      coordinates (the local driver plus any rivals in view). The rest is HUD
      copy — whichever of [place] / [time_elapsed] is [Some] is shown on the
      right. *)
  type t =
    { viewport : Map_state.Viewport.t
    ; cell_size : float
    ; cars : Car.t list
    ; track_name : string
    ; lap : int
    ; laps_to_win : int
    ; speed : Speed.t option
    ; place : int option
    ; time_elapsed : Time_ns.Span.t option
    ; window_w : int
    ; window_h : int
    }
end

(** Pure: the full back-to-front geometry of one frame. *)
val scene_of_frame : Frame.t -> Prim.t list

(** Open the [Graphics] window sized to the frame, with double buffering on.
    Call once before {!draw_frame}. *)
val open_window : Frame.t -> unit

(** Clear, draw {!scene_of_frame}, and flip the buffer. *)
val draw_frame : Frame.t -> unit
