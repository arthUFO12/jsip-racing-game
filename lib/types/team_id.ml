open! Core

module T = struct
  type t = int [@@deriving compare, equal, hash, sexp]
end

include T
include Comparable.Make (T)
include Hashable.Make (T)

let of_int t = t
let to_int t = t
