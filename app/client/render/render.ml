open! Core
open Racing_map
open Racing_types
open Prim

module Car = struct
  type t =
    { pos : Position.t
    ; heading : Heading.t
    ; team : Team_id.t
    ; is_self : bool
    ; effects : Effect.t list
    }
end

module Frame = struct
  type t =
    { viewport : Map_state.Viewport.t
    ; cell_size : float
    ; cars : Car.t list
    ; track_name : string
    ; lap : int
    ; laps_to_win : int
    ; speed : Speed.t option
    ; place : int option
    ; time_elapsed : Time_ns.Span.t option
    ; window_w : int
    ; window_h : int
    }
end

(* Chrome sizes, in pixels. *)
let bezel_px = 16
let hud_height = 52
let hud_gap = 10

(* Cockpit glass — a cool tint the shared palette has no name for; kept local
   the way the other view-specific inks are. *)
let windshield_glass = Color.rgb 150 196 224

(* --- small geometry helpers --- *)

let rotate ~cx ~cy ~theta (lx, ly) =
  let ct = Float.cos theta
  and st = Float.sin theta in
  ( cx + Float.iround_nearest_exn ((lx *. ct) -. (ly *. st))
  , cy + Float.iround_nearest_exn ((lx *. st) +. (ly *. ct)) )
;;

(* --- terrain --- *)

(* Structured (never random) per-cell texture, all lit from the top-left: the
   lit shade goes up/left of a feature, the shaded one down/right, so a field
   of cells reads as one coherently-lit surface rather than noise. *)
let tile_texture
  ~add
  ~x
  ~y
  ~size
  ~(surface : Surface.t)
  ~(environment : Environment.t)
  ~base
  =
  let line x1 y1 x2 y2 color =
    add (Line { x1; y1; x2; y2; width = 1; color })
  in
  match surface with
  | Road ->
    (* a faint paved-tile bevel: lit top edge, shaded bottom edge *)
    line x (y + size - 1) (x + size) (y + size - 1) (Color.lighten base ~frac:0.08);
    line x y (x + size) y (Color.darken base ~frac:0.14)
  | Trees ->
    let clump dx dy r shade =
      add
        (Fill_ellipse
           { x = x + dx; y = y + dy; rx = Int.max 1 r; ry = Int.max 1 r; color = shade })
    in
    (* canopy: shaded lobe down-right, then the lit crown up-left, then a
       bright highlight where the light lands *)
    clump (2 * size / 3) (size / 3) (size / 4) (Color.darken base ~frac:0.18);
    clump (2 * size / 5) (3 * size / 5) (size / 4) (Color.lighten base ~frac:0.12);
    clump (size / 3) (2 * size / 3) (size / 8) (Color.lighten base ~frac:0.26)
  | Wall ->
    (match environment with
     | Castle ->
       (* a raised cut-stone block: lit top, shaded bottom, one mortar seam *)
       line x (y + size - 1) (x + size) (y + size - 1) (Color.lighten base ~frac:0.14);
       line x y (x + size) y (Color.darken base ~frac:0.26);
       line x (y + (size / 2)) (x + size) (y + (size / 2)) (Color.darken base ~frac:0.2);
       line (x + (size / 2)) y (x + (size / 2)) (y + (size / 2)) (Color.darken base ~frac:0.2)
     | Forest | Cave ->
       let dot dx dy r shade =
         add
           (Fill_ellipse
              { x = x + dx
              ; y = y + dy
              ; rx = Int.max 1 r
              ; ry = Int.max 1 r
              ; color = shade
              })
       in
       (* rounded boulder: shaded flank down-right, lit crown up-left, speck *)
       dot (3 * size / 5) (2 * size / 5) (size / 4) (Color.darken base ~frac:0.16);
       dot (2 * size / 5) (3 * size / 5) (size / 4) (Color.lighten base ~frac:0.12);
       dot (size / 3) (2 * size / 3) (size / 10) (Color.lighten base ~frac:0.24))
;;

(* --- features --- *)

let draw_bridge ~add ~boxes ~size ~(phase : Feature.Bridge.Phase.t) =
  List.iter boxes ~f:(fun (x, y) ->
    match phase with
    | Intact ->
      add
        (Fill_rect { x; y; w = size; h = size; color = Palette.bridge_plank });
      let seam i =
        add
          (Line
             { x1 = x
             ; y1 = y + (i * size / 4)
             ; x2 = x + size
             ; y2 = y + (i * size / 4)
             ; width = 1
             ; color = Color.darken Palette.bridge_plank ~frac:0.28
             })
      in
      seam 1;
      seam 2;
      seam 3;
      add
        (Line
           { x1 = x
           ; y1 = y
           ; x2 = x
           ; y2 = y + size
           ; width = 2
           ; color = Color.lighten Palette.bridge_plank ~frac:0.18
           })
    | Collapsing { falls_at = _ } ->
      add
        (Fill_rect { x; y; w = size; h = size; color = Palette.bridge_plank });
      add
        (Line
           { x1 = x
           ; y1 = y
           ; x2 = x + size
           ; y2 = y + size
           ; width = 2
           ; color = Palette.telegraph
           });
      add
        (Line
           { x1 = x
           ; y1 = y + size
           ; x2 = x + size
           ; y2 = y
           ; width = 2
           ; color = Color.darken Palette.bridge_plank ~frac:0.4
           })
    | Collapsed { rebuilt_at = _ } ->
      add (Fill_rect { x; y; w = size; h = size; color = Palette.water });
      add
        (Fill_ellipse
           { x = x + (size / 2)
           ; y = y + (size / 2)
           ; rx = size / 3
           ; ry = size / 8
           ; color = Palette.water_highlight
           });
      add
        (Fill_ellipse
           { x = x + (size / 3)
           ; y = y + (size / 3)
           ; rx = size / 6
           ; ry = size / 12
           ; color = Palette.rim_light
           }))
;;

let draw_gate ~add ~boxes ~size ~(phase : Feature.Gate.Phase.t) =
  let teeth = [ 1; 2; 3; 4 ] in
  List.iter boxes ~f:(fun (x, y) ->
    match phase with
    | Open ->
      add
        (Line
           { x1 = x
           ; y1 = y + size - 2
           ; x2 = x + size
           ; y2 = y + size - 2
           ; width = 3
           ; color = Palette.gate_iron
           });
      List.iter teeth ~f:(fun k ->
        add
          (Line
             { x1 = x + (k * size / 5)
             ; y1 = y + size
             ; x2 = x + (k * size / 5)
             ; y2 = y + size - (size / 5)
             ; width = 2
             ; color = Palette.gate_bar
             }))
    | Closing { shut_at = _ } ->
      add
        (Line
           { x1 = x
           ; y1 = y + size - 2
           ; x2 = x + size
           ; y2 = y + size - 2
           ; width = 3
           ; color = Palette.gate_iron
           });
      List.iter teeth ~f:(fun k ->
        add
          (Line
             { x1 = x + (k * size / 5)
             ; y1 = y + size
             ; x2 = x + (k * size / 5)
             ; y2 = y + (size / 2)
             ; width = 2
             ; color = Palette.telegraph
             }))
    | Closed { reopens_at = _ } ->
      add (Fill_rect { x; y; w = size; h = size; color = Palette.gate_iron });
      List.iter teeth ~f:(fun k ->
        add
          (Line
             { x1 = x + (k * size / 5)
             ; y1 = y
             ; x2 = x + (k * size / 5)
             ; y2 = y + size
             ; width = 2
             ; color = Palette.gate_bar
             }));
      add
        (Line
           { x1 = x
           ; y1 = y + (size / 3)
           ; x2 = x + size
           ; y2 = y + (size / 3)
           ; width = 2
           ; color = Palette.gate_bar
           });
      add
        (Line
           { x1 = x
           ; y1 = y + (2 * size / 3)
           ; x2 = x + size
           ; y2 = y + (2 * size / 3)
           ; width = 2
           ; color = Palette.gate_bar
           }))
;;

let draw_stalactite ~add ~boxes ~size ~(phase : Feature.Stalactite.Phase.t) =
  List.iter boxes ~f:(fun (x, y) ->
    let spike dx =
      Fill_poly
        { points =
            [| x + dx, y + size
             ; x + dx + (size / 6), y + size
             ; x + dx + (size / 12), y + size - (size / 3)
            |]
        ; color = Palette.stalactite
        }
    in
    match phase with
    | Hanging ->
      add (spike (size / 6));
      add (spike (size / 2));
      add (spike (2 * size / 3))
    | Falling { lands_at = _ } ->
      add
        (Fill_ellipse
           { x = x + (size / 2)
           ; y = y + (size / 4)
           ; rx = size / 3
           ; ry = size / 8
           ; color = Palette.car_shadow
           });
      add
        (Fill_poly
           { points =
               [| x + (size / 2) - (size / 8), y + (2 * size / 3)
                ; x + (size / 2) + (size / 8), y + (2 * size / 3)
                ; x + (size / 2), y + (size / 3)
               |]
           ; color = Palette.stalactite
           });
      add
        (Line
           { x1 = x
           ; y1 = y + size
           ; x2 = x + size
           ; y2 = y + size
           ; width = 2
           ; color = Palette.danger
           })
    | Debris { cleared_at = _ } ->
      add (Fill_rect { x; y; w = size; h = size; color = Palette.debris });
      add
        (Fill_ellipse
           { x = x + (size / 3)
           ; y = y + (size / 3)
           ; rx = size / 5
           ; ry = size / 6
           ; color = Color.darken Palette.debris ~frac:0.18
           });
      add
        (Fill_ellipse
           { x = x + (2 * size / 3)
           ; y = y + (size / 2)
           ; rx = size / 6
           ; ry = size / 7
           ; color = Color.lighten Palette.debris ~frac:0.12
           }))
;;

let draw_ice ~add ~boxes ~size =
  List.iter boxes ~f:(fun (x, y) ->
    add (Fill_rect { x; y; w = size; h = size; color = Palette.ice });
    let facet dx dy s =
      Fill_poly
        { points =
            [| x + dx, y + dy + s
             ; x + dx + s, y + dy
             ; x + dx, y + dy - s
             ; x + dx - s, y + dy
            |]
        ; color = Palette.ice_shine
        }
    in
    add (facet (size / 3) (2 * size / 3) (size / 8));
    add (facet (2 * size / 3) (size / 3) (size / 10));
    add
      (Rect
         { x
         ; y
         ; w = size
         ; h = size
         ; color = Color.lighten Palette.ice ~frac:0.1
         }))
;;

let draw_feature ~add ~cam ~cell_px feature =
  let { Feature.id = _; cells; payload } = feature in
  let boxes = List.map cells ~f:(Camera.cell_origin_px cam) in
  match payload with
  | Feature.Payload.Bridge b ->
    draw_bridge ~add ~boxes ~size:cell_px ~phase:b.Feature.Bridge.phase
  | Feature.Payload.Gate g ->
    draw_gate ~add ~boxes ~size:cell_px ~phase:g.Feature.Gate.phase
  | Feature.Payload.Stalactite s ->
    draw_stalactite
      ~add
      ~boxes
      ~size:cell_px
      ~phase:s.Feature.Stalactite.phase
  | Feature.Payload.Ice_patch _ -> draw_ice ~add ~boxes ~size:cell_px
;;

(* --- cars --- *)

let has_effect (car : Car.t) ~kind =
  List.exists car.effects ~f:(fun e -> Effect.Kind.equal e.Effect.kind kind)
;;

let boosting car =
  has_effect car ~kind:(Effect.Kind.Powerup Powerup.Speed_boost)
;;

let gliding car = has_effect car ~kind:(Effect.Kind.Powerup Powerup.Glider)

let invincible car =
  has_effect car ~kind:(Effect.Kind.Powerup Powerup.Invincibility)
;;

let vined car = has_effect car ~kind:Effect.Kind.Vines

let draw_car ~add ~cam ~(car : Car.t) =
  let cx, cy = Camera.world_px cam car.pos in
  let size = Camera.cell_px cam in
  let theta = Heading.to_radians car.heading in
  let hl = Float.of_int size *. 0.42 in
  let hw = Float.of_int size *. 0.26 in
  let corner lx ly = rotate ~cx ~cy ~theta (lx, ly) in
  let livery = Palette.team car.team in
  (* Soft contact shadow, thrown down-right of the car to match the light. *)
  add
    (Fill_ellipse
       { x = cx + (size / 12)
       ; y = cy - (size / 6)
       ; rx = Int.max 2 (size * 2 / 5)
       ; ry = Int.max 1 (size / 6)
       ; color = Palette.car_shadow
       });
  if invincible car
  then (
    (* a two-ring shimmer rather than a flat disc *)
    add
      (Fill_ellipse
         { x = cx; y = cy; rx = size / 2; ry = size / 2; color = Palette.shield });
    add
      (Fill_ellipse
         { x = cx
         ; y = cy
         ; rx = size * 2 / 5
         ; ry = size * 2 / 5
         ; color = Color.lighten Palette.shield ~frac:0.35
         }));
  if boosting car
  then (
    let tip = corner (-.hl -. (Float.of_int size *. 0.35)) 0. in
    add
      (Fill_poly
         { points =
             [| corner (-.hl) (hw *. 0.6); corner (-.hl) (-.hw *. 0.6); tip |]
         ; color = Palette.boost_flame
         });
    add
      (Fill_poly
         { points =
             [| corner (-.hl) (hw *. 0.3)
              ; corner (-.hl) (-.hw *. 0.3)
              ; corner (-.hl -. (Float.of_int size *. 0.2)) 0.
             |]
         ; color = Palette.hud_accent
         }));
  if gliding car
  then (
    add
      (Fill_poly
         { points =
             [| corner (hl *. 0.2) hw
              ; corner (-.hl *. 0.4) (hw *. 2.1)
              ; corner (-.hl *. 0.7) (hw *. 1.9)
             |]
         ; color = Palette.glider_wing
         });
    add
      (Fill_poly
         { points =
             [| corner (hl *. 0.2) (-.hw)
              ; corner (-.hl *. 0.4) (-.hw *. 2.1)
              ; corner (-.hl *. 0.7) (-.hw *. 1.9)
             |]
         ; color = Palette.glider_wing
         }));
  (* Rounded, nose-tapered hull so the silhouette reads as a car, not a box. *)
  add
    (Fill_poly
       { points =
           [| corner hl (hw *. 0.5)
            ; corner (hl *. 0.5) hw
            ; corner (-.hl *. 0.85) hw
            ; corner (-.hl) (hw *. 0.55)
            ; corner (-.hl) (-.hw *. 0.55)
            ; corner (-.hl *. 0.85) (-.hw)
            ; corner (hl *. 0.5) (-.hw)
            ; corner hl (-.hw *. 0.5)
           |]
       ; color = livery
       });
  (* Shaded tail grounds the hull; the lit nose wedge doubles as the heading. *)
  add
    (Fill_poly
       { points =
           [| corner (-.hl *. 0.2) hw
            ; corner (-.hl) (hw *. 0.55)
            ; corner (-.hl) (-.hw *. 0.55)
            ; corner (-.hl *. 0.2) (-.hw)
           |]
       ; color = Color.darken livery ~frac:0.24
       });
  add
    (Fill_poly
       { points =
           [| corner (hl *. 1.02) 0.
            ; corner (hl *. 0.45) (hw *. 0.72)
            ; corner (hl *. 0.45) (-.hw *. 0.72)
           |]
       ; color = Color.lighten livery ~frac:0.26
       });
  add
    (Fill_poly
       { points =
           [| corner (hl *. 0.4) (hw *. 0.62)
            ; corner (hl *. 0.4) (-.hw *. 0.62)
            ; corner (-.hl *. 0.05) (-.hw *. 0.62)
            ; corner (-.hl *. 0.05) (hw *. 0.62)
           |]
       ; color = windshield_glass
       });
  let gx1, gy1 = corner (hl *. 0.36) (hw *. 0.5) in
  let gx2, gy2 = corner (-.hl *. 0.02) (hw *. 0.2) in
  add
    (Line { x1 = gx1; y1 = gy1; x2 = gx2; y2 = gy2; width = 1; color = Palette.rim_light });
  if vined car
  then
    List.iter [ -0.5; 0.0; 0.5 ] ~f:(fun t ->
      let ax, ay = corner (hl *. t) hw
      and bx, by = corner (hl *. t) (-.hw) in
      add
        (Line
           { x1 = ax; y1 = ay; x2 = bx; y2 = by; width = 2; color = Palette.vines }));
  if car.is_self
  then (
    (* a pinned marker floating above the local driver *)
    add
      (Fill_poly
         { points =
             [| cx, cy + (size * 3 / 4)
              ; cx - (size / 6), cy + size
              ; cx + (size / 6), cy + size
             |]
         ; color = Palette.hud_accent
         });
    add
      (Fill_poly
         { points =
             [| cx, cy + (size * 4 / 5)
              ; cx - (size / 10), cy + size
              ; cx + (size / 10), cy + size
             |]
         ; color = Palette.hud_title
         }))
;;

(* --- HUD --- *)

(* One panel look, shared by every HUD widget. Light falls from the top-left,
   so a soft shadow drops down-right, the top and left inner edges are lit and
   the bottom and right are shaded, then a crisp border seals it. This bevel
   is what turns a flat rectangle into something that reads as a raised plate. *)
let panel ~add ~x ~y ~w ~h =
  let hi = Color.lighten Palette.hud_panel ~frac:0.2 in
  let lo = Color.darken Palette.hud_panel ~frac:0.3 in
  add (Fill_rect { x = x + 3; y = y - 3; w; h; color = Palette.hud_shadow });
  add (Fill_rect { x; y; w; h; color = Palette.hud_panel });
  add
    (Line
       { x1 = x + 1
       ; y1 = y + h - 1
       ; x2 = x + w - 1
       ; y2 = y + h - 1
       ; width = 1
       ; color = hi
       });
  add
    (Line
       { x1 = x + 1; y1 = y + 1; x2 = x + 1; y2 = y + h - 1; width = 1; color = hi });
  add
    (Line
       { x1 = x + 1; y1 = y + 1; x2 = x + w - 1; y2 = y + 1; width = 1; color = lo });
  add
    (Line
       { x1 = x + w - 1
       ; y1 = y + 1
       ; x2 = x + w - 1
       ; y2 = y + h - 1
       ; width = 1
       ; color = lo
       });
  add (Rect { x; y; w; h; color = Palette.hud_border })
;;

let format_time span =
  let total = Float.max 0. (Time_ns.Span.to_sec span) in
  let minutes = Float.to_int (total /. 60.) in
  let seconds = Float.to_int (Float.mod_float total 60.) in
  let tenths = Float.to_int (Float.mod_float (total *. 10.) 10.) in
  sprintf "%d:%02d:%d" minutes seconds tenths
;;

let ordinal n =
  let suffix =
    match n % 100 with
    | 11 | 12 | 13 -> "th"
    | _ ->
      (match n % 10 with 1 -> "st" | 2 -> "nd" | 3 -> "rd" | _ -> "th")
  in
  sprintf "%d%s" n suffix
;;

let draw_hud ~add ~(frame : Frame.t) =
  let { Frame.track_name
      ; lap
      ; laps_to_win
      ; place
      ; time_elapsed
      ; speed
      ; window_w
      ; window_h
      ; _
      }
    =
    frame
  in
  let hud_y = window_h - bezel_px - hud_height in
  let text_y = hud_y + (hud_height / 2) - 6 in
  let left_w = 150
  and right_w = 190 in
  panel ~add ~x:bezel_px ~y:hud_y ~w:left_w ~h:hud_height;
  add
    (Text
       { x = bezel_px + 14
       ; y = text_y
       ; s = sprintf "LAP %d/%d" lap laps_to_win
       ; size = `Large
       ; color = Palette.hud_text
       });
  let right_x = window_w - bezel_px - right_w in
  panel ~add ~x:right_x ~y:hud_y ~w:right_w ~h:hud_height;
  (match place, time_elapsed with
   | Some p, _ ->
     add
       (Text
          { x = right_x + 14
          ; y = text_y
          ; s = "POS"
          ; size = `Large
          ; color = Palette.hud_text
          });
     add
       (Text
          { x = right_x + 78
          ; y = text_y
          ; s = ordinal p
          ; size = `Large
          ; color = Palette.hud_accent
          })
   | None, Some span ->
     add
       (Text
          { x = right_x + 14
          ; y = text_y
          ; s = "TIME"
          ; size = `Large
          ; color = Palette.hud_text
          });
     add
       (Text
          { x = right_x + 88
          ; y = text_y
          ; s = format_time span
          ; size = `Large
          ; color = Palette.hud_title
          })
   | None, None -> ());
  let center_x = bezel_px + left_w + 8 in
  let center_w = right_x - 8 - center_x in
  panel ~add ~x:center_x ~y:hud_y ~w:center_w ~h:hud_height;
  let approx_char_px = 9 in
  let title_x =
    center_x
    + Int.max
        12
        ((center_w - (String.length track_name * approx_char_px)) / 2)
  in
  add
    (Text
       { x = title_x
       ; y = text_y
       ; s = track_name
       ; size = `Large
       ; color = Palette.hud_title
       });
  match speed with
  | None -> ()
  | Some spd ->
    let sw = 118
    and sh = 30 in
    let sx = bezel_px + 6
    and sy = bezel_px + 6 in
    panel ~add ~x:sx ~y:sy ~w:sw ~h:sh;
    add
      (Text
         { x = sx + 10
         ; y = sy + 8
         ; s =
             sprintf "SPD %d" (Float.iround_nearest_exn (Speed.to_float spd))
         ; size = `Small
         ; color = Palette.hud_text
         })
;;

(* --- scene assembly --- *)

let scene_of_frame (frame : Frame.t) =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  let { Frame.viewport; cell_size; cars; window_w; window_h; _ } = frame in
  let { Map_state.Viewport.origin
      ; surfaces
      ; environments
      ; features
      ; is_dark
      }
    =
    viewport
  in
  add
    (Fill_rect
       { x = 0; y = 0; w = window_w; h = window_h; color = Palette.bezel });
  let area_x = bezel_px in
  let area_y = bezel_px in
  let area_w = window_w - (2 * bezel_px) in
  let area_h = window_h - (2 * bezel_px) - hud_height - hud_gap in
  let rows = Array.length surfaces in
  let cols = if rows = 0 then 0 else Array.length surfaces.(0) in
  let n_cells = Int.max 1 (Int.max rows cols) in
  let cam =
    Camera.create
      ~origin
      ~cells:n_cells
      ~cell_size
      ~area_x
      ~area_y
      ~area_w
      ~area_h
  in
  let cpx = Camera.cell_px cam in
  (* terrain *)
  for r = 0 to rows - 1 do
    for c = 0 to cols - 1 do
      let surface = surfaces.(r).(c) in
      let environment = environments.(r).(c) in
      let cell = { Cell.col = origin.col + c; row = origin.row + r } in
      let x, y = Camera.cell_origin_px cam cell in
      let base = Palette.ground ~surface ~environment in
      let base =
        if is_dark
        then Color.mix base Palette.cave_shade ~frac:0.45
        else base
      in
      add (Fill_rect { x; y; w = cpx; h = cpx; color = base });
      tile_texture ~add ~x ~y ~size:cpx ~surface ~environment ~base
    done
  done;
  (* feature overlays *)
  List.iter features ~f:(draw_feature ~add ~cam ~cell_px:cpx);
  (* cars, local driver's on top *)
  let cars =
    List.stable_sort cars ~compare:(fun a b ->
      Bool.compare a.Car.is_self b.Car.is_self)
  in
  List.iter cars ~f:(fun car -> draw_car ~add ~cam ~car);
  (* frame the play area, then the HUD *)
  add
    (Rect
       { x = area_x - 2
       ; y = area_y - 2
       ; w = area_w + 4
       ; h = area_h + 4
       ; color = Color.lighten Palette.bezel ~frac:0.18
       });
  draw_hud ~add ~frame;
  Queue.to_list out
;;

(* --- OCaml Graphics backend --- *)

let set_color color = Graphics.set_color (Prim.Color.to_graphics color)

let draw_prim (p : Prim.t) =
  match p with
  | Fill_rect { x; y; w; h; color } ->
    set_color color;
    Graphics.fill_rect x y w h
  | Rect { x; y; w; h; color } ->
    set_color color;
    Graphics.draw_rect x y w h
  | Fill_poly { points; color } ->
    set_color color;
    Graphics.fill_poly points
  | Fill_ellipse { x; y; rx; ry; color } ->
    set_color color;
    Graphics.fill_ellipse x y rx ry
  | Line { x1; y1; x2; y2; width; color } ->
    set_color color;
    Graphics.set_line_width width;
    Graphics.moveto x1 y1;
    Graphics.lineto x2 y2
  | Text { x; y; s; size; color } ->
    set_color color;
    Graphics.set_text_size (match size with `Large -> 18 | `Small -> 12);
    Graphics.moveto x y;
    Graphics.draw_string s
;;

let open_window (frame : Frame.t) =
  Graphics.open_graph (sprintf " %dx%d" frame.window_w frame.window_h);
  Graphics.set_window_title "JSIP Racing — Driver";
  Graphics.auto_synchronize false
;;

let draw_frame frame =
  Graphics.clear_graph ();
  List.iter (scene_of_frame frame) ~f:draw_prim;
  Graphics.synchronize ()
;;
