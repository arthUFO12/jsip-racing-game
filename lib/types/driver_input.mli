open! Core

(** The state of the driver's movement keys (WASD) at one input tick:
    "holding down accelerates, letting go decelerates". This is the only
    thing a driver client ever sends — see [driver_input_rpc] in
    [doc/rpc-protocol.md]. (That doc still sketches a heading+throttle input;
    this type supersedes it and the doc needs updating.)

    It is pure intent, not physics. The server integrates it: holding
    [accelerate] speeds the car toward its top speed, releasing lets drag
    slow it down, [steer_left]/[steer_right] rotate the {!Heading.t} over
    time, and active powerdowns (vines, ice) apply server-side. The result
    comes back as {!Velocity.t} in the next snapshot.

    Every value of this type is legal — four booleans, nothing to validate
    (contrast {!Heading.of_radians}, which has to reject junk). Holding
    opposing keys at once is fine: they cancel. *)

type t =
  { accelerate : bool (** W *)
  ; brake : bool (** S *)
  ; steer_left : bool (** A *)
  ; steer_right : bool (** D *)
  }
[@@deriving compare, equal, sexp_of]

(** No keys held. *)
val idle : t
