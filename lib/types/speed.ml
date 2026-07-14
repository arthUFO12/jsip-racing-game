open! Core

type t = float [@@deriving bin_io, compare, equal, sexp_of]

let zero = 0.

let of_float speed =
  if Float.is_finite speed && Float.O.(speed >= 0.)
  then Ok speed
  else
    Or_error.error_s
      [%message "speed must be finite and non-negative" (speed : float)]
;;

let of_float_exn speed = ok_exn (of_float speed)
let to_float t = t
