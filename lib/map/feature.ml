open! Core

module Bridge = struct
  module Phase = struct
    type t =
      | Intact
      | Collapsing of { falls_at : Tick.t }
      | Collapsed of { rebuilt_at : Tick.t }
    [@@deriving sexp, bin_io, compare, equal]
  end

  type t = { phase : Phase.t } [@@deriving sexp, bin_io, compare, equal]
end

module Gate = struct
  module Phase = struct
    type t =
      | Open
      | Closing of { shut_at : Tick.t }
      | Closed of { reopens_at : Tick.t }
    [@@deriving sexp, bin_io, compare, equal]
  end

  type t = { phase : Phase.t } [@@deriving sexp, bin_io, compare, equal]
end

module Stalactite = struct
  module Phase = struct
    type t =
      | Hanging
      | Falling of { lands_at : Tick.t }
      | Debris of { cleared_at : Tick.t }
    [@@deriving sexp, bin_io, compare, equal]
  end

  type t = { phase : Phase.t } [@@deriving sexp, bin_io, compare, equal]
end

module Ice_patch = struct
  type t = { melts_at : Tick.t } [@@deriving sexp, bin_io, compare, equal]
end

module Payload = struct
  type t =
    | Bridge of Bridge.t
    | Gate of Gate.t
    | Stalactite of Stalactite.t
    | Ice_patch of Ice_patch.t
  [@@deriving sexp, bin_io, compare, equal]
end

module Kind = struct
  type t =
    | Bridge
    | Gate
    | Stalactite
    | Ice_patch
  [@@deriving sexp, bin_io, compare, equal, enumerate]
end

type t =
  { id : Feature_id.t
  ; cells : Cell.t list
  ; payload : Payload.t
  }
[@@deriving sexp, bin_io, compare, equal]

let kind t : Kind.t =
  match t.payload with
  | Bridge (_ : Bridge.t) -> Bridge
  | Gate (_ : Gate.t) -> Gate
  | Stalactite (_ : Stalactite.t) -> Stalactite
  | Ice_patch (_ : Ice_patch.t) -> Ice_patch
;;

(* Provisional tuning. Once a physics/config module exists, gameplay
   constants like this should probably move there. *)
let ice_traction = 0.3

let surface_override t =
  match t.payload with
  | Gate { phase = Closed _ } -> Some Surface.Wall
  | Gate { phase = Open | Closing _ } -> None
  | Stalactite { phase = Debris _ } -> Some Surface.Wall
  | Stalactite { phase = Hanging | Falling _ } -> None
  | Bridge (_ : Bridge.t) -> None
  | Ice_patch (_ : Ice_patch.t) -> None
;;

let is_gap t =
  match t.payload with
  | Bridge { phase = Collapsed _ } -> true
  | Bridge { phase = Intact | Collapsing _ } -> false
  | Gate (_ : Gate.t) | Stalactite (_ : Stalactite.t) -> false
  | Ice_patch (_ : Ice_patch.t) -> false
;;

let traction_multiplier t =
  match t.payload with
  | Ice_patch (_ : Ice_patch.t) -> ice_traction
  | Bridge (_ : Bridge.t) | Gate (_ : Gate.t) -> 1.0
  | Stalactite (_ : Stalactite.t) -> 1.0
;;
