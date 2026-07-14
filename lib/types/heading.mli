open! Core

(** The direction a car points, in radians counterclockwise from the positive
    x axis, always normalized: at least [0.], strictly below
    [2. *. Float.pi].

    Abstract so a heading can't be mixed up with a speed or any other float —
    and so every heading in the system is already normalized: "an angle of 17
    pi" is unrepresentable.

    {[
      Heading.of_radians_exn (5. *. Float.pi) |> Heading.to_radians
      (* = Float.pi *)
    ]}

    ([bin_io] is a machine format for RPC transport and skips normalization;
    headings only travel server-to-client, so every heading on the wire was
    normalized when the server constructed it.) *)

type t [@@deriving bin_io, compare, equal, sexp_of]

(** Pointing along the positive x axis. *)
val zero : t

(** Errors on NaN and infinities — clients can send us any float — otherwise
    normalizes into the range above. *)
val of_radians : float -> t Or_error.t

(** Like {!of_radians}, but raises. For call sites that already know the
    float is finite (server-side math, test setup). *)
val of_radians_exn : float -> t

val to_radians : t -> float
