open! Core

type t =
  { id : Team_id.t
  ; driver : Player.t
  ; track_player : Player.t
  }
[@@deriving compare, equal, sexp_of]

let create ~id ~(driver : Player.t) ~(track_player : Player.t) =
  if Player_id.equal driver.id track_player.id
  then
    Or_error.error_s
      [%message
        "a team needs two different players"
          ~player:(driver.id : Player_id.t)]
  else Ok { id; driver; track_player }
;;

let role (t : t) player_id =
  if Player_id.equal player_id t.driver.id
  then Some Role.Driver
  else if Player_id.equal player_id t.track_player.id
  then Some Role.Track_player
  else None
;;
