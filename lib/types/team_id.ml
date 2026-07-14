open! Core

module T = struct
  type t = int [@@deriving bin_io, compare, equal, hash, sexp]
end

include T
include Comparable.Make_binable (T)
include Hashable.Make (T)

let of_int t = t
let to_int t = t
