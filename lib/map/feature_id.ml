open! Core

module T = struct
  type t = int [@@deriving sexp, bin_io, compare, equal, hash]
end

include T

(* [Make_binable] (not [Make]) so [Feature_id.Map.t] can cross the wire
   inside [Map_state.t]. *)
include Comparable.Make_binable (T)
include Hashable.Make (T)

let of_int t = t
let to_int t = t
