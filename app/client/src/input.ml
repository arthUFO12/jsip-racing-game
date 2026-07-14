open! Core

module Key = struct
  type t =
    | W
    | A
    | S
    | D
    | Digit of int
  [@@deriving compare, equal, hash, sexp_of]

  let of_char = function
    | 'w' | 'W' -> Some W
    | 'a' | 'A' -> Some A
    | 's' | 'S' -> Some S
    | 'd' | 'D' -> Some D
    | '0' .. '9' as c -> Some (Digit (Char.to_int c - Char.to_int '0'))
    | _ -> None
  ;;
end

let auto_repeat_timeout = Time_ns.Span.of_int_ms 500

let now () =
  Time_ns.of_int63_ns_since_epoch (Time_now.nanoseconds_since_unix_epoch ())
;;

type t =
  { keypress_handlers : (unit -> unit) list Hashtbl.M(Key).t
      (* Handlers keyed by the key they respond to, so dispatch is a single
         lookup rather than a broadcast to every handler. [add_multi]
         prepends, so each list is most-recently-registered first. *)
  ; mutable click_handlers : (x:int -> y:int -> unit) list
  ; mutable button_was_down : bool
      (* Mouse button state as of the previous [poll], for click edge
         detection: [Graphics.button_down] reports the live state, not a
         queue of click events. *)
  ; last_press_at : Time_ns.t Hashtbl.M(Key).t
  (* When each key's press event was last drained. [Graphics] has no
     key-release events, so [is_pressed] synthesizes held-state from OS
     auto-repeat: held keys keep re-arriving in the queue, refreshing this
     timestamp; a stale timestamp means released. *)
  }

let create () =
  { keypress_handlers = Hashtbl.create (module Key)
  ; click_handlers = []
  ; button_was_down = false
  ; last_press_at = Hashtbl.create (module Key)
  }
;;

let on_keypress t key ~f = Hashtbl.add_multi t.keypress_handlers ~key ~data:f
let on_click t ~f = t.click_handlers <- t.click_handlers @ [ f ]

(* Keys arrive in a buffered queue: [Graphics.key_pressed] says whether the
   queue is non-empty, [Graphics.read_key] pops one. Drain the whole queue
   each frame so held-down typing can't back up across frames. *)
let drain_keys t =
  while Graphics.key_pressed () do
    match Key.of_char (Graphics.read_key ()) with
    | None -> ()
    | Some key ->
      Hashtbl.set t.last_press_at ~key ~data:(now ());
      (* [rev] restores registration order — see the field comment. *)
      Hashtbl.find_multi t.keypress_handlers key
      |> List.rev
      |> List.iter ~f:(fun f -> f ())
  done
;;

(* Unlike keys, mouse clicks have no queue: [Graphics.button_down ()] is the
   live button state and [Graphics.mouse_pos ()] the live cursor position. A
   "click" must be derived by comparing this frame's button state to
   [t.button_was_down] (edge detection). *)
let poll_mouse t =
  let button_is_down = Graphics.button_down () in
  (match t.button_was_down, button_is_down with
   | false, true ->
     (* Down-transition: fire on press for responsiveness. *)
     let x, y = Graphics.mouse_pos () in
     List.iter t.click_handlers ~f:(fun f -> f ~x ~y)
   | false, false | true, true | true, false -> ());
  t.button_was_down <- button_is_down
;;

let poll t =
  drain_keys t;
  poll_mouse t
;;

let is_pressed t key =
  match Hashtbl.find t.last_press_at key with
  | None -> false
  | Some last_press ->
    Time_ns.Span.( <= )
      (Time_ns.diff (now ()) last_press)
      auto_repeat_timeout
;;
