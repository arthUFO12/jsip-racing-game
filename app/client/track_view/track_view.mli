(** The track player's (co-pilot's) whole-map console: the entire track seen
    from above, every car as a dot, and a right-hand control panel showing
    the race status, the co-pilot's item stock, and the live threats they can
    sabotage with.

    Like {!Jsip_client_render.Render} it is split pure / impure so most of it
    is testable without a window:

    - {!scene_of_frame} turns a {!Frame.t} into a flat {!Prim.t} [list] — no
      side effects — so a whole console frame's geometry is expect-testable
      and the same scene can be replayed by any backend.
    - {!open_window} / {!draw_frame} are the only impure part: they push that
      scene to an OCaml [Graphics] window.

    A {!Frame.t} is assembled by a trivial adapter (living in the client)
    from the map handed out at login plus the per-tick game snapshot. This
    library deliberately depends only on the map, the domain types and
    {!Jsip_client_render} — never on the gateway or Async — so the adapter,
    not this code, owns the protocol shape. *)

open! Core
open Racing_types
open Racing_map
module Prim = Jsip_client_render.Prim

module Car_view : sig
  (** One car to plot on the map: a render-side view (position, facing, team
      livery, plus [name] and [laps_completed] for the console) rather than a
      shared domain car. [is_own_driver] marks the co-pilot's own teammate,
      which is drawn with a bright ring. *)
  type t =
    { position : Position.t
    ; velocity : Velocity.t
    ; team : Team_id.t
    ; name : string
    ; laps_completed : int
    ; is_own_driver : bool
    }
end

module Frame : sig
  (** Everything one console frame needs. [game_map] is the immutable layout,
      [track] the live feature state (bridges, gates, stalactites, ice),
      [cars] the cars to plot in world coordinates, [inventory] the
      co-pilot's own stock (rendered as per-item counts), [race_status] the
      phase of the race, and [selected] an optional sabotage-target cursor. *)
  type t =
    { game_map : Game_map.t
    ; track : Map_state.t
    ; cars : Car_view.t list
    ; inventory : Powerup.t list
    ; race_status : Race_status.t
    ; selected : Cell.t option
    ; window_w : int
    ; window_h : int
    }
end

(** Pure: the full back-to-front geometry of one console frame, in y-up pixel
    space. *)
val scene_of_frame : Frame.t -> Prim.t list

(** Open the [Graphics] window sized to the frame, double-buffered. Call once
    before {!draw_frame}. *)
val open_window : Frame.t -> unit

(** Clear, draw {!scene_of_frame}, and flip the buffer. *)
val draw_frame : Frame.t -> unit
