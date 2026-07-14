open! Core
open Racing_types

type t =
  | Collapse_bridge of Feature_id.t
  | Close_gate of Feature_id.t
  | Drop_stalactite of Feature_id.t
  | Place_ice of Position.t
[@@deriving sexp, bin_io, compare, equal]
