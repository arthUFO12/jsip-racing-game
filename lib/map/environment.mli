(** The theme zone a cell sits in. Orthogonal to {!Surface}: a [Road] cell
    can run through any environment. Environments drive the client's
    palette, darkness ({!is_dark}), and where certain powers are legal —
    stalactites hang only over [Cave] cells; vines (a car status effect,
    not map state) only make sense in [Forest]. *)

open! Core

type t =
  | Forest
  | Castle
  | Cave
[@@deriving sexp, bin_io, compare, equal, enumerate]

(** [Cave] only. The driver client renders darkness over dark cells unless
    the car's flashlight is lit — car state the map never sees. *)
val is_dark : t -> bool
