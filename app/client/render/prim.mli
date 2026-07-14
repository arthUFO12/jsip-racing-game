(** Backend-independent 2D drawing primitives in pixel space, plus the RGB
    colors they carry. A [t list] is one frame's worth of geometry:
    {!Render.scene_of_frame} builds one as pure data — so a whole frame is
    expect-testable without ever opening a window — and a backend
    ({!Render.draw_frame} over OCaml [Graphics]) executes it.

    Coordinates are y-up with the origin at the bottom-left, matching both the
    [Graphics] window and {!Racing_types.Position}, so nothing downstream ever
    flips an axis. Everything is integer pixels; the float world-to-pixel
    conversion happens once, in {!Camera}. *)

open! Core

module Color : sig
  (** A packed [0xRRGGBB] color, bit-compatible with [Graphics.color] (so the
      backend passes {!to_graphics} straight to [Graphics.set_color]). Renders
      in sexps as [#rrggbb] to keep expect tests legible. *)
  type t [@@deriving compare, equal, sexp_of]

  (** Channels are clamped to [0 .. 255]. *)
  val rgb : int -> int -> int -> t

  val to_graphics : t -> int

  (** Blend two colors: [mix a b ~frac:0.] is [a], [~frac:1.] is [b]. Used for
      telegraph flashes (mix toward amber) and cave shading. *)
  val mix : t -> t -> frac:float -> t

  (** [mix] toward black / toward white — shorthands for shadows and shine. *)
  val darken : t -> frac:float -> t

  val lighten : t -> frac:float -> t
end

type t =
  | Fill_rect of
      { x : int
      ; y : int
      ; w : int
      ; h : int
      ; color : Color.t
      }
  | Rect of
      { x : int
      ; y : int
      ; w : int
      ; h : int
      ; color : Color.t
      } (** outline only *)
  | Fill_poly of
      { points : (int * int) array
      ; color : Color.t
      }
  | Fill_ellipse of
      { x : int (** center *)
      ; y : int
      ; rx : int
      ; ry : int
      ; color : Color.t
      }
  | Line of
      { x1 : int
      ; y1 : int
      ; x2 : int
      ; y2 : int
      ; width : int
      ; color : Color.t
      }
  | Text of
      { x : int (** lower-left of the string *)
      ; y : int
      ; s : string
      ; size : [ `Small | `Large ]
      ; color : Color.t
      }
[@@deriving sexp_of]
