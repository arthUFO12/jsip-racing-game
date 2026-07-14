open! Core

(** Where the race is in its lifecycle, as broadcast in every snapshot.
    Constructors are bare for now; payloads (time left in the countdown,
    final standings for [Finished]) are server-design decisions that haven't
    been made yet — grow them here when they are. *)

type t =
  | Countdown (** everyone's in; cars locked until the green light *)
  | Racing
  | Finished
[@@deriving bin_io, compare, enumerate, equal, sexp_of]
