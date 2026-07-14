(** Pure HUD widgets and race overlays. Each function returns a [Prim.t list]
    — a bundle of drawing fragments — to composite over any already-rendered
    view (the {!Render} scene, a spectator view, whatever). Nothing here
    opens a window or touches Async: the widgets are the same immutable
    [Prim.t] data a {!Render} frame is made of, so every one is
    expect-testable without a display.

    Coordinates are y-up with the origin at the bottom-left, matching {!Prim}
    and the rest of the client. Anchor arguments name a {e corner} of the
    widget: [leaderboard]/[inventory_bar]/[effect_chips] take an [(x, y)] and
    grow in the direction each doc comment states. The full-screen overlays
    ([countdown], [finish_board]) instead take the [window_w]/[window_h] they
    should cover and center themselves.

    Colours come from {!Palette}; anything Palette doesn't name (glyph inks,
    the countdown scrim, the mud-bomb brown) is defined locally in [hud.ml]
    rather than by growing the shared palette. *)

open! Core
open Racing_types
module Prim = Jsip_client_render.Prim

(** A big centered countdown over a dim scrim; [count=0] renders "GO!". The
    digit reads as a large accent ring with the number inside, since
    {!Prim.Text} is too small to be a hero element on its own. *)
val countdown : count:int -> window_w:int -> window_h:int -> Prim.t list

module Standing : sig
  (** One driver's line on a board: [place] is their rank (1 = winner),
      [name] the display name, [team] the livery to swatch, and [laps] the
      number of laps completed. *)
  type t =
    { place : int
    ; name : string
    ; team : Team_id.t
    ; laps : int
    }
  [@@deriving sexp_of]
end

(** Full-screen end-of-race standings board; winner highlighted. Rows are
    drawn in [place] order regardless of input order. *)
val finish_board
  :  Standing.t list
  -> window_w:int
  -> window_h:int
  -> Prim.t list

(** Compact live leaderboard strip anchored at [(x, y)] (its top-left), rows
    grow downward. Names are truncated to keep the strip narrow. *)
val leaderboard : Standing.t list -> x:int -> y:int -> Prim.t list

(** Held-items bar: one glyph tile per powerup with an [xN] count, laid out
    left-to-right from [(x, y)] (the bottom-left of the first tile). *)
val inventory_bar : (Powerup.t * int) list -> x:int -> y:int -> Prim.t list

(** Active effects as chips with integer remaining-seconds, laid out
    left-to-right from [(x, y)] (the bottom-left of the first chip). *)
val effect_chips : Effect.t list -> x:int -> y:int -> Prim.t list
