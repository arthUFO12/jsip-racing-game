(* The co-pilot's whole-map console. [scene_of_frame] is pure geometry — the
   whole track top-down plus a right-hand control panel — and the [Graphics]
   backend at the bottom mirrors {!Jsip_client_render.Render}. Coordinates
   are y-up pixels (see {!Prim}); the float world-to-pixel conversion happens
   once, in {!Camera}. *)

open! Core
open Racing_types
open Racing_map
module Prim = Jsip_client_render.Prim
module Palette = Jsip_client_render.Palette
module Camera = Jsip_client_render.Camera
open Prim

module Car_view = struct
  type t =
    { position : Position.t
    ; velocity : Velocity.t
    ; team : Team_id.t
    ; name : string
    ; laps_completed : int
    ; is_own_driver : bool
    }
end

module Frame = struct
  type t =
    { game_map : Game_map.t
    ; track : Map_state.t
    ; cars : Car_view.t list
    ; inventory : Powerup.t list
    ; race_status : Race_status.t
    ; selected : Cell.t option
    ; window_w : int
    ; window_h : int
    }
end

(* Chrome sizes, in pixels. *)
let bezel_px = 16
let panel_w = 260
let panel_gap = 12
let line_h = 22

(* Two colors the shared {!Palette} has no name for: the two counter-powerups
   whose glyphs would otherwise collide with the flame/shield ones. Kept
   local per the "don't edit Palette" rule. *)
let flashlight_beam = Color.rgb 240 224 120
let axe_steel = Color.rgb 176 186 198

(* --- small geometry helper --- *)

let rotate ~cx ~cy ~theta (lx, ly) =
  let ct = Float.cos theta
  and st = Float.sin theta in
  ( cx + Float.iround_nearest_exn ((lx *. ct) -. (ly *. st))
  , cy + Float.iround_nearest_exn ((lx *. st) +. (ly *. ct)) )
;;

(* --- features: one compact glyph per cell, keyed by payload + phase --- *)

let bridge_glyph ~add ~x ~y ~size ~(phase : Feature.Bridge.Phase.t) =
  match phase with
  | Intact ->
    add
      (Fill_rect { x; y; w = size; h = size; color = Palette.bridge_plank });
    add
      (Line
         { x1 = x
         ; y1 = y + (size / 2)
         ; x2 = x + size
         ; y2 = y + (size / 2)
         ; width = 1
         ; color = Color.darken Palette.bridge_plank ~frac:0.3
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
         })
  | Collapsed { rebuilt_at = _ } ->
    add (Fill_rect { x; y; w = size; h = size; color = Palette.water });
    add
      (Fill_ellipse
         { x = x + (size / 2)
         ; y = y + (size / 2)
         ; rx = Int.max 1 (size / 3)
         ; ry = Int.max 1 (size / 6)
         ; color = Palette.water_highlight
         })
;;

let gate_glyph ~add ~x ~y ~size ~(phase : Feature.Gate.Phase.t) =
  let bars color =
    List.iter [ 1; 2; 3 ] ~f:(fun k ->
      add
        (Line
           { x1 = x + (k * size / 4)
           ; y1 = y
           ; x2 = x + (k * size / 4)
           ; y2 = y + size
           ; width = 1
           ; color
           }))
  in
  let teeth ~bottom color =
    List.iter [ 1; 2; 3 ] ~f:(fun k ->
      add
        (Line
           { x1 = x + (k * size / 4)
           ; y1 = y + size
           ; x2 = x + (k * size / 4)
           ; y2 = bottom
           ; width = 1
           ; color
           }))
  in
  match phase with
  | Open ->
    add
      (Line
         { x1 = x
         ; y1 = y + size - 1
         ; x2 = x + size
         ; y2 = y + size - 1
         ; width = 2
         ; color = Palette.gate_iron
         });
    teeth ~bottom:(y + (2 * size / 3)) Palette.gate_bar
  | Closing { shut_at = _ } ->
    add
      (Line
         { x1 = x
         ; y1 = y + size - 1
         ; x2 = x + size
         ; y2 = y + size - 1
         ; width = 2
         ; color = Palette.gate_iron
         });
    teeth ~bottom:(y + (size / 3)) Palette.telegraph
  | Closed { reopens_at = _ } ->
    add (Fill_rect { x; y; w = size; h = size; color = Palette.gate_iron });
    bars Palette.gate_bar
;;

let stalactite_glyph ~add ~x ~y ~size ~(phase : Feature.Stalactite.Phase.t) =
  let spike dx color =
    Fill_poly
      { points =
          [| x + dx, y + size
           ; x + dx + (size / 4), y + size
           ; x + dx + (size / 8), y + size - (size / 2)
          |]
      ; color
      }
  in
  match phase with
  | Hanging ->
    add (spike (size / 6) Palette.stalactite);
    add (spike (size / 2) Palette.stalactite)
  | Falling { lands_at = _ } ->
    add (spike (size / 3) Palette.telegraph);
    add
      (Fill_ellipse
         { x = x + (size / 2)
         ; y = y + (size / 4)
         ; rx = Int.max 1 (size / 4)
         ; ry = Int.max 1 (size / 8)
         ; color = Palette.car_shadow
         })
  | Debris { cleared_at = _ } ->
    add (Fill_rect { x; y; w = size; h = size; color = Palette.debris })
;;

let ice_glyph ~add ~x ~y ~size =
  add (Fill_rect { x; y; w = size; h = size; color = Palette.ice });
  let cx = x + (size / 2)
  and cy = y + (size / 2) in
  let s = Int.max 1 (size / 4) in
  add
    (Fill_poly
       { points = [| cx, cy + s; cx + s, cy; cx, cy - s; cx - s, cy |]
       ; color = Palette.ice_shine
       })
;;

let draw_feature ~add ~cam ~cell_px (feature : Feature.t) =
  let { Feature.id = _; cells; payload } = feature in
  List.iter cells ~f:(fun cell ->
    let x, y = Camera.cell_origin_px cam cell in
    match payload with
    | Feature.Payload.Bridge b ->
      bridge_glyph ~add ~x ~y ~size:cell_px ~phase:b.Feature.Bridge.phase
    | Feature.Payload.Gate g ->
      gate_glyph ~add ~x ~y ~size:cell_px ~phase:g.Feature.Gate.phase
    | Feature.Payload.Stalactite s ->
      stalactite_glyph
        ~add
        ~x
        ~y
        ~size:cell_px
        ~phase:s.Feature.Stalactite.phase
    | Feature.Payload.Ice_patch _ -> ice_glyph ~add ~x ~y ~size:cell_px)
;;

(* --- checkpoints and the start grid --- *)

let start_finish_index = 0

let draw_checkpoints ~add ~cam ~cell_size checkpoints =
  Array.iter checkpoints ~f:(fun (cp : Checkpoint.t) ->
    let color, width =
      if cp.index = start_finish_index
      then Palette.hud_accent, 3
      else Palette.hud_text, 2
    in
    let pts =
      List.map cp.cells ~f:(fun cell ->
        Camera.world_px cam (Cell.center cell ~cell_size))
    in
    match pts with
    | [] -> ()
    | [ (x, y) ] -> add (Fill_ellipse { x; y; rx = 2; ry = 2; color })
    | (x1, y1) :: rest ->
      let x2, y2 = List.last_exn rest in
      add (Line { x1; y1; x2; y2; width; color }))
;;

let draw_start_grid ~add ~cam poses =
  let size = Camera.cell_px cam in
  let r = Float.of_int (Int.max 4 (size / 3)) in
  List.iter poses ~f:(fun (pose : Pose.t) ->
    let cx, cy = Camera.world_px cam pose.pos in
    let pt lx ly = rotate ~cx ~cy ~theta:pose.heading (lx, ly) in
    add
      (Fill_poly
         { points =
             [| pt r 0.
              ; pt (-.r *. 0.7) (r *. 0.6)
              ; pt (-.r *. 0.7) (-.r *. 0.6)
             |]
         ; color = Palette.hud_title
         }))
;;

(* --- cars --- *)

let draw_car ~add ~cam ~(car : Car_view.t) =
  let cx, cy = Camera.world_px cam car.position in
  let size = Camera.cell_px cam in
  let r = Int.max 3 (size / 3) in
  let rf = Float.of_int r in
  let { Velocity.heading; speed = _ } = car.velocity in
  let theta = Heading.to_radians heading in
  let livery = Palette.team car.team in
  let pt lx ly = rotate ~cx ~cy ~theta (lx, ly) in
  let off = Int.max 1 (r / 4) in
  (* contact shadow, down-right of the disc *)
  add
    (Fill_ellipse
       { x = cx + off; y = cy - off; rx = r; ry = r; color = Palette.car_shadow });
  (* the co-pilot's own driver wears a bright ring *)
  if car.is_own_driver
  then
    add
      (Fill_ellipse
         { x = cx; y = cy; rx = r + 2; ry = r + 2; color = Palette.hud_accent });
  (* a nose triangle points where the car is heading — clearer than a stick *)
  add
    (Fill_poly
       { points =
           [| pt (rf *. 1.8) 0.
            ; pt (rf *. 0.3) (rf *. 0.85)
            ; pt (rf *. 0.3) (-.rf *. 0.85)
           |]
       ; color = Color.darken livery ~frac:0.28
       });
  add (Fill_ellipse { x = cx; y = cy; rx = r; ry = r; color = livery });
  (* a top-left glint gives the disc a little roundness *)
  let g = Int.max 1 (r / 3) in
  add
    (Fill_ellipse
       { x = cx - g
       ; y = cy + g
       ; rx = g
       ; ry = g
       ; color = Color.lighten livery ~frac:0.3
       })
;;

(* --- selection cursor --- *)

let draw_selected ~add ~cam ~cell_px cell =
  let x, y = Camera.cell_origin_px cam cell in
  add (Rect { x; y; w = cell_px; h = cell_px; color = Palette.hud_accent });
  add
    (Rect
       { x = x - 1
       ; y = y - 1
       ; w = cell_px + 2
       ; h = cell_px + 2
       ; color = Palette.hud_accent
       })
;;

(* --- right-hand control panel --- *)

let race_status_text (status : Race_status.t) =
  match status with
  | Countdown -> "COUNTDOWN"
  | Racing -> "RACING"
  | Finished -> "FINISHED"
;;

(* Collapse an inventory into (item, count) rows, one per distinct powerup,
   in {!Powerup} declaration order (the map comparator's order). *)
let inventory_counts inventory =
  List.fold inventory ~init:Powerup.Map.empty ~f:(fun acc p ->
    Map.update acc p ~f:(function None -> 1 | Some n -> n + 1))
  |> Map.to_alist
;;

let powerup_glyph ~add ~x ~y ~size (p : Powerup.t) =
  let cx = x + (size / 2)
  and cy = y + (size / 2) in
  match p with
  | Speed_boost ->
    add
      (Fill_poly
         { points = [| x, y; x, y + size; x + size, cy |]
         ; color = Palette.boost_flame
         })
  | Invincibility ->
    add
      (Fill_ellipse
         { x = cx
         ; y = cy
         ; rx = size / 2
         ; ry = size / 2
         ; color = Palette.shield
         })
  | Glider ->
    add
      (Fill_poly
         { points = [| x, cy; x + size, y + size; x + size, y |]
         ; color = Palette.glider_wing
         })
  | Flame_magic ->
    add
      (Fill_poly
         { points = [| cx, y; x, y + size; x + size, y + size |]
         ; color = Palette.danger
         })
  | Flashlight ->
    add
      (Fill_poly
         { points =
             [| x, y
              ; x + size, y + (size / 3)
              ; x + size, y + (2 * size / 3)
             |]
         ; color = flashlight_beam
         })
  | Axe ->
    add
      (Fill_rect
         { x; y = y + (size / 3); w = size; h = size / 3; color = axe_steel })
;;

let feature_line (feature : Feature.t) =
  let kind =
    match Feature.kind feature with
    | Feature.Kind.Bridge -> "Bridge"
    | Feature.Kind.Gate -> "Gate"
    | Feature.Kind.Stalactite -> "Stalactite"
    | Feature.Kind.Ice_patch -> "Ice"
  in
  let phase =
    match feature.payload with
    | Feature.Payload.Bridge b ->
      (match b.Feature.Bridge.phase with
       | Intact -> "intact"
       | Collapsing _ -> "collapsing"
       | Collapsed _ -> "gap")
    | Feature.Payload.Gate g ->
      (match g.Feature.Gate.phase with
       | Open -> "open"
       | Closing _ -> "closing"
       | Closed _ -> "closed")
    | Feature.Payload.Stalactite s ->
      (match s.Feature.Stalactite.phase with
       | Hanging -> "hanging"
       | Falling _ -> "falling"
       | Debris _ -> "debris")
    | Feature.Payload.Ice_patch _ -> "slick"
  in
  sprintf "%s: %s" kind phase
;;

(* The one panel look, mirroring {!Jsip_client_render.Render.panel}: a soft
   drop shadow down-right, lit top/left edges and shaded bottom/right edges
   (light from the top-left), then a crisp border. *)
let beveled_panel ~add ~x ~y ~w ~h =
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

let draw_panel ~add ~(frame : Frame.t) ~px ~py ~pw ~ph =
  beveled_panel ~add ~x:px ~y:py ~w:pw ~h:ph;
  let left = px + 14 in
  let top = py + ph - 14 in
  let line n = top - 14 - (n * line_h) in
  add
    (Text
       { x = left
       ; y = line 0
       ; s = Game_map.name frame.game_map
       ; size = `Large
       ; color = Palette.hud_title
       });
  add
    (Text
       { x = left
       ; y = line 1
       ; s = race_status_text frame.race_status
       ; size = `Large
       ; color = Palette.hud_accent
       });
  (* inventory: one row per distinct held powerup *)
  let inv_header = line 2 - 8 in
  add
    (Text
       { x = left
       ; y = inv_header
       ; s = "ITEMS"
       ; size = `Small
       ; color = Palette.hud_text
       });
  let counts = inventory_counts frame.inventory in
  List.iteri counts ~f:(fun i (p, n) ->
    let row_y = inv_header - ((i + 1) * line_h) in
    powerup_glyph ~add ~x:left ~y:(row_y - 2) ~size:16 p;
    add
      (Text
         { x = left + 24
         ; y = row_y
         ; s = sprintf "x%d" n
         ; size = `Small
         ; color = Palette.hud_text
         }));
  (* threats: the live features and their phase *)
  let threats_header =
    inv_header - ((List.length counts + 1) * line_h) - 8
  in
  add
    (Text
       { x = left
       ; y = threats_header
       ; s = "THREATS"
       ; size = `Small
       ; color = Palette.hud_text
       });
  List.iteri (Map_state.features frame.track) ~f:(fun i feature ->
    add
      (Text
         { x = left
         ; y = threats_header - ((i + 1) * line_h)
         ; s = feature_line feature
         ; size = `Small
         ; color = Palette.hud_text
         }))
;;

(* --- camera / hit-testing ---

   The map is drawn in the left region (inside the bezel, left of the panel).
   [camera_of_frame] is the single source of that layout, so {!cell_at_px}
   (click -> cell) and {!scene_of_frame} (cell -> pixels) can never disagree. *)

let camera_of_frame (frame : Frame.t) =
  let panel_x = frame.window_w - bezel_px - panel_w in
  let area_x = bezel_px in
  let area_y = bezel_px in
  let area_w = panel_x - panel_gap - bezel_px in
  let area_h = frame.window_h - (2 * bezel_px) in
  let cols = Game_map.cols frame.game_map in
  let rows = Game_map.rows frame.game_map in
  Camera.create
    ~origin:{ Cell.col = 0; row = 0 }
    ~cells:(Int.max 1 (Int.max cols rows))
    ~cell_size:(Game_map.cell_size frame.game_map)
    ~area_x
    ~area_y
    ~area_w
    ~area_h
;;

let cell_at_px (frame : Frame.t) ~x ~y =
  let cell = Camera.cell_of_px (camera_of_frame frame) ~x ~y in
  let cols = Game_map.cols frame.game_map in
  let rows = Game_map.rows frame.game_map in
  if cell.Cell.col >= 0 && cell.col < cols && cell.row >= 0 && cell.row < rows
  then Some cell
  else None
;;

(* --- scene assembly --- *)

let scene_of_frame (frame : Frame.t) =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  let { Frame.game_map; track; cars; selected; window_w; window_h; _ } =
    frame
  in
  (* background *)
  add
    (Fill_rect
       { x = 0; y = 0; w = window_w; h = window_h; color = Palette.bezel });
  (* regions: a left map area and a right panel, each inside the bezel *)
  let panel_x = window_w - bezel_px - panel_w in
  let panel_y = bezel_px in
  let panel_h = window_h - (2 * bezel_px) in
  let area_x = bezel_px in
  let area_y = bezel_px in
  let area_w = panel_x - panel_gap - bezel_px in
  let area_h = window_h - (2 * bezel_px) in
  let cols = Game_map.cols game_map in
  let rows = Game_map.rows game_map in
  let cell_size = Game_map.cell_size game_map in
  let cam = camera_of_frame frame in
  let cpx = Camera.cell_px cam in
  (* terrain: one composed fill per cell, darkened in the caves *)
  for row = 0 to rows - 1 do
    for col = 0 to cols - 1 do
      let cell = { Cell.col; row } in
      let environment = Game_map.environment_at game_map cell in
      let surface =
        Map_state.surface_at
          track
          ~map:game_map
          (Cell.center cell ~cell_size)
      in
      let x, y = Camera.cell_origin_px cam cell in
      let base = Palette.ground ~surface ~environment in
      let base =
        if Environment.is_dark environment
        then Color.mix base Palette.cave_shade ~frac:0.45
        else base
      in
      (* A faint checkerboard shading (no extra primitives) gives the flat
         top-down tiles a woven, paved texture instead of one dead colour. *)
      let base =
        if (row + col) land 1 = 0
        then Color.lighten base ~frac:0.035
        else Color.darken base ~frac:0.035
      in
      add (Fill_rect { x; y; w = cpx; h = cpx; color = base })
    done
  done;
  (* feature overlays *)
  List.iter
    (Map_state.features track)
    ~f:(draw_feature ~add ~cam ~cell_px:cpx);
  (* checkpoints then start grid *)
  draw_checkpoints ~add ~cam ~cell_size (Game_map.checkpoints game_map);
  draw_start_grid ~add ~cam (Game_map.start_grid game_map);
  (* cars, the co-pilot's own driver drawn last so it lands on top *)
  let cars =
    List.stable_sort cars ~compare:(fun a b ->
      Bool.compare a.Car_view.is_own_driver b.Car_view.is_own_driver)
  in
  List.iter cars ~f:(fun car -> draw_car ~add ~cam ~car);
  (* sabotage-target cursor *)
  (match selected with
   | None -> ()
   | Some cell -> draw_selected ~add ~cam ~cell_px:cpx cell);
  (* frame the play area, then the panel *)
  add
    (Rect
       { x = area_x - 2
       ; y = area_y - 2
       ; w = area_w + 4
       ; h = area_h + 4
       ; color = Color.lighten Palette.bezel ~frac:0.18
       });
  draw_panel ~add ~frame ~px:panel_x ~py:panel_y ~pw:panel_w ~ph:panel_h;
  Queue.to_list out
;;

(* --- OCaml Graphics backend (mirrors {!Jsip_client_render.Render}) --- *)

let set_color color = Graphics.set_color (Color.to_graphics color)

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
  Graphics.set_window_title "JSIP Racing — Track Control";
  Graphics.auto_synchronize false
;;

let draw_frame frame =
  Graphics.clear_graph ();
  List.iter (scene_of_frame frame) ~f:draw_prim;
  Graphics.synchronize ()
;;
