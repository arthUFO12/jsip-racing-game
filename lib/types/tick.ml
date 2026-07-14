open! Core

module T = struct
  type t = int [@@deriving bin_io, compare, equal, hash, sexp]
end

include T
include Comparable.Make (T)

let zero = 0
let next t = t + 1
let add t n = t + n
let of_int t = t
let to_int t = t
