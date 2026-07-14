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

  let is_steer = function
    | A | D -> true
    | W | S | Digit _ -> false
  ;;
end

(* [Graphics] gives key presses but no releases, so held-state is synthesized
   from OS key auto-repeat. A fresh press holds for [initial_hold] — long
   enough to span the OS delay before auto-repeat starts — and each repeat
   re-arms a short [sustain], so releasing a key registers within a frame or
   two instead of lingering half a second. A press within [repeat_gap] of the
   previous one for that key is treated as a repeat, not a fresh press. *)
let initial_hold = Time_ns.Span.of_int_ms 500
let sustain = Time_ns.Span.of_int_ms 150
let repeat_gap = Time_ns.Span.of_int_ms 250

(* X auto-repeats only the {e newest} held key, so pressing A while holding W
   stops W's repeats and W would read as released — you could not accelerate
   and steer at once. To fix that, a steering event also keeps an
   already-held throttle key (W/S) alive, as long as that throttle was really
   pressed within [throttle_grace] (so it still lets go a beat after you
   actually release it). *)
let throttle_grace = Time_ns.Span.of_int_ms 900
let throttle_keys = [ Key.W; Key.S ]

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
      (* When each key last produced an event — used to tell a fresh press
         from an auto-repeat, and to bound how long steering keeps a throttle
         alive after it stops repeating. *)
  ; held_until : Time_ns.t Hashtbl.M(Key).t
      (* When each key stops counting as held. {!is_pressed} is just [now <=
         this]. *)
  }

let create () =
  { keypress_handlers = Hashtbl.create (module Key)
  ; click_handlers = []
  ; button_was_down = false
  ; last_press_at = Hashtbl.create (module Key)
  ; held_until = Hashtbl.create (module Key)
  }
;;

let on_keypress t key ~f = Hashtbl.add_multi t.keypress_handlers ~key ~data:f
let on_click t ~f = t.click_handlers <- t.click_handlers @ [ f ]

(* A held throttle whose own last press is still within [throttle_grace] gets
   its held window extended, so it survives a steering key stealing the OS
   auto-repeat. *)
let sustain_throttles t ~now =
  List.iter throttle_keys ~f:(fun key ->
    match Hashtbl.find t.held_until key, Hashtbl.find t.last_press_at key with
    | Some until, Some last
      when Time_ns.( >= ) until now
           && Time_ns.Span.( <= ) (Time_ns.diff now last) throttle_grace ->
      Hashtbl.set t.held_until ~key ~data:(Time_ns.add now sustain)
    | _ -> ())
;;

let register_press t key ~now =
  let is_repeat =
    match Hashtbl.find t.last_press_at key with
    | Some prev -> Time_ns.Span.( <= ) (Time_ns.diff now prev) repeat_gap
    | None -> false
  in
  let hold = if is_repeat then sustain else initial_hold in
  Hashtbl.set t.last_press_at ~key ~data:now;
  Hashtbl.set t.held_until ~key ~data:(Time_ns.add now hold);
  if Key.is_steer key then sustain_throttles t ~now
;;

(* Keys arrive in a buffered queue: [Graphics.key_pressed] says whether the
   queue is non-empty, [Graphics.read_key] pops one. Drain the whole queue
   each frame so held-down typing can't back up across frames. *)
let drain_keys t =
  while Graphics.key_pressed () do
    match Key.of_char (Graphics.read_key ()) with
    | None -> ()
    | Some key ->
      register_press t key ~now:(now ());
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
  match Hashtbl.find t.held_until key with
  | None -> false
  | Some until -> Time_ns.( <= ) (now ()) until
;;
