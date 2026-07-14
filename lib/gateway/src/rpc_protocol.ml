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
