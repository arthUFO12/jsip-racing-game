open! Core

type t = float [@@deriving bin_io, compare, equal, sexp_of]

let zero = 0.
let two_pi = 2. *. Float.pi

let of_radians radians =
  if Float.is_finite radians
  then (
    let r = Float.mod_float radians two_pi in
    let r = if Float.O.(r < 0.) then r +. two_pi else r in
    (* [r +. two_pi] can round up to exactly [two_pi] when [r] is a tiny
       negative number, which would break the "strictly below 2 pi" promise. *)
    Ok (if Float.O.(r >= two_pi) then 0. else r))
  else
    Or_error.error_s
      [%message "heading must be a finite angle" (radians : float)]
;;

let of_radians_exn radians = ok_exn (of_radians radians)
let to_radians t = t
