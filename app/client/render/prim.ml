open! Core

module Color = struct
  (* Packed 0xRRGGBB, exactly the [Graphics.color] encoding. *)
  type t = int [@@deriving compare, equal]

  let clamp channel = Int.max 0 (Int.min 255 channel)
  let rgb r g b = (clamp r lsl 16) lor (clamp g lsl 8) lor clamp b
  let to_graphics t = t
  let red t = (t lsr 16) land 0xff
  let green t = (t lsr 8) land 0xff
  let blue t = t land 0xff
  let sexp_of_t t = Sexp.Atom (sprintf "#%06x" t)

  let mix a b ~frac =
    let frac = Float.max 0. (Float.min 1. frac) in
    let blend ca cb =
      Float.iround_nearest_exn
        ((Float.of_int ca *. (1. -. frac)) +. (Float.of_int cb *. frac))
    in
    rgb
      (blend (red a) (red b))
      (blend (green a) (green b))
      (blend (blue a) (blue b))
  ;;

  let black = rgb 0 0 0
  let white = rgb 255 255 255
  let darken t ~frac = mix t black ~frac
  let lighten t ~frac = mix t white ~frac
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
      }
  | Fill_poly of
      { points : (int * int) array
      ; color : Color.t
      }
  | Fill_ellipse of
      { x : int
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
      { x : int
      ; y : int
      ; s : string
      ; size : [ `Small | `Large ]
      ; color : Color.t
      }
[@@deriving sexp_of]
