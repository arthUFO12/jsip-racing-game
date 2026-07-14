open! Core

type t =
  { accelerate : bool
  ; brake : bool
  ; steer_left : bool
  ; steer_right : bool
  }
[@@deriving compare, equal, sexp_of]

let idle =
  { accelerate = false
  ; brake = false
  ; steer_left = false
  ; steer_right = false
  }
;;
