open! Core

(** A player's display name, as typed by a human when joining — so it is
    validated here, at the edge, and nothing downstream has to re-check it.

    Rules: 1 to {!max_length} characters, drawn from letters, digits, ['_']
    and ['-'].

    There is deliberately no [t_of_sexp] and no unchecked constructor: the
    only way to obtain a [Player_name.t] is {!of_string}, so an invalid name
    is unrepresentable. Names are for display only and are not guaranteed
    unique — key data structures by {!Player_id.t} instead. *)

type t [@@deriving compare, equal, sexp_of]

(** Validates the rules above, reporting every rule the string breaks rather
    than just the first. [of_string "Robyn"] is [Ok]; [of_string ""] is an
    [Error]. *)
val of_string : string -> t Or_error.t

val to_string : t -> string
val max_length : int
