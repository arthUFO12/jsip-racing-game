open! Core

type t =
  { x : float
  ; y : float
  }
[@@deriving sexp, bin_io, compare, equal]

let zero = { x = 0.; y = 0. }
let add a b = { x = a.x +. b.x; y = a.y +. b.y }
let sub a b = { x = a.x -. b.x; y = a.y -. b.y }
let scale t ~by = { x = t.x *. by; y = t.y *. by }

let distance a b =
  let dx = a.x -. b.x in
  let dy = a.y -. b.y in
  Float.sqrt ((dx *. dx) +. (dy *. dy))
;;
