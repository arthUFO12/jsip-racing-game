open! Core
open Racing_types

(* The RPC descriptions are transport-agnostic, so they take [Rpc] from
   [async_rpc_kernel] rather than the full [Async] library: anything that
   only needs the wire protocol stays free of Unix dependencies. *)
module Rpc = Async_rpc_kernel.Rpc

module Join_request = struct
  type t =
    { name : string
    ; team : Team_id.t
    ; role : Role.t
    }
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Car = struct
  type t =
    { position : Position.t
    ; velocity : Velocity.t
    }
  [@@deriving bin_io, compare, equal, sexp_of]
end

module Game_snapshot = struct
  type t =
    { tick : Tick.t
    ; race_status : Race_status.t
    ; teams : Team.t list
    ; cars : Car.t Player_id.Map.t
    ; effects : Effect.t list Player_id.Map.t
    ; inventories : Powerup.t list Player_id.Map.t
    }
  [@@deriving bin_io, sexp_of]
end

module Interference = struct
  (* A track player's sabotage comes in two halves that live in two different
     libraries: [Racing_types.Interference] — powerdowns aimed at a rival
     driver (vines, mud) — and [Racing_map.Track_action] — actions that alter
     the track itself (collapse a bridge, close a gate, drop a stalactite,
     pour ice). Neither can reference the other: the map library depends on
     the types library, not the reverse. The protocol sits above both, so it
     unions them here — wrapping the two existing types rather than
     re-listing a single constructor of either. *)
  type t =
    | On_driver of Racing_types.Interference.t
    | On_track of Racing_map.Track_action.t
  [@@deriving bin_io, compare, equal, sexp_of]
end

let join_game_rpc =
  Rpc.Rpc.create
    ~name:"join-game"
    ~version:1
    ~bin_query:Join_request.bin_t
    ~bin_response:[%bin_type_class: Player_id.t Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

let game_feed_rpc =
  Rpc.Pipe_rpc.create
    ~name:"game-feed"
    ~version:1
    ~bin_query:Unit.bin_t
    ~bin_response:Game_snapshot.bin_t
    ~bin_error:Error.bin_t
    ()
;;

let driver_input_rpc =
  Rpc.One_way.create
    ~name:"driver-input"
    ~version:1
    ~bin_msg:Driver_input.bin_t
;;

let use_powerup_rpc =
  Rpc.Rpc.create
    ~name:"use-powerup"
    ~version:1
    ~bin_query:Powerup.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

let use_interference_rpc =
  Rpc.Rpc.create
    ~name:"use-interference"
    ~version:1
    ~bin_query:Interference.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

let assist_teammate_rpc =
  Rpc.Rpc.create
    ~name:"assist-teammate"
    ~version:1
    ~bin_query:Powerup.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;
