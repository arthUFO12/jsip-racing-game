(** Keyboard and mouse input collection for the racing client.

    Wraps the polling [Graphics] input API in a per-frame dispatch model:
    call {!poll} once per render tick and it drains all pending input,
    running the handlers registered with {!on_keypress} and {!on_click}.
    [poll] never blocks — a frame with no input dispatches nothing.

    Only inputs the game cares about are surfaced: WASD (driving), digits 0-9
    (e.g. inventory slots), and mouse clicks (e.g. track-player interference
    targeting). All other keys are ignored.

    Example:
    {[
      let input = Input.create () in
      Input.on_keypress input W ~f:(fun () -> accelerate ());
      Input.on_click input ~f:(fun ~x ~y -> target_interference ~x ~y);
      (* in the render loop: *)
      Input.poll input
    ]} *)

open! Core

module Key : sig
  (** A key the game responds to. *)
  type t =
    | W
    | A
    | S
    | D
    | Digit of int (** 0-9, e.g. selecting an inventory slot *)
  [@@deriving compare, equal, hash, sexp_of]
end

type t

(** [create ()] makes an input collector with no handlers registered. The
    [Graphics] window must be open before the first {!poll}. *)
val create : unit -> t

(** Register [f] to run on every press of [key]. Multiple handlers for the
    same key run in registration order; keys with no handlers cost nothing to
    dispatch. *)
val on_keypress : t -> Key.t -> f:(unit -> unit) -> unit

(** Register [f] to run on every mouse click, with window-relative pixel
    coordinates (origin at the bottom-left, as in [Graphics]). *)
val on_click : t -> f:(x:int -> y:int -> unit) -> unit

(** Drain all pending input and dispatch to registered handlers. Call once
    per frame from the render loop. *)
val poll : t -> unit

(** [is_pressed t key] reports whether [key] is currently held down.

    [Graphics] delivers no key-release events, so held-state is synthesized
    from OS key auto-repeat: a fresh press counts as held long enough to span
    the OS delay before repeats begin, and each repeat re-arms a short window,
    so a release registers within a frame or two rather than lingering. Since
    X auto-repeats only the most-recently pressed key, a steering key ([A]/[D])
    also keeps an already-held throttle key ([W]/[S]) alive briefly — so
    accelerating and steering at the same time works.

    Only meaningful if {!poll} runs every frame — that is what refreshes the
    underlying press timing. *)
val is_pressed : t -> Key.t -> bool
