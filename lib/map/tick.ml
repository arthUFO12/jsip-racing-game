open! Core

module T = struct
  type t = int [@@deriving sexp, bin_io, compare, equal, hash]
end

include T
include Comparable.Make (T)

let zero = 0
let next t = t + 1
let add t n = t + n
