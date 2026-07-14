(* Detailed, pure sprite fragments for the driver view plus a whole-track
   minimap. Each function returns primitive geometry for a given pixel box
   (y-up, origin bottom-left); see the mli for the contract. The richer
   cousins of Jsip_client_render.Render's flat tiles live here so the driver
   scene can stay a thin assembler. *)

open! Core
open Racing_map
open Racing_types
module Color = Prim.Color

(* Tints not in the shared palette, kept local by design. *)
let trunk_wood = Color.rgb 92 62 38
let wheel_rubber = Color.rgb 26 24 28
let windshield_glass = Color.rgb 150 196 224
let headlight_glow = Color.rgb 255 244 200
let number_ink = Color.rgb 245 245 245
let pole_wood = Color.rgb 74 60 44

(* Rotate local coords [(lx, ly)] by [theta] radians about [(cx, cy)], to
   integer pixels — the same trick as Jsip_client_render.Render.rotate. *)
let rotate ~cx ~cy ~theta (lx, ly) =
  let ct = Float.cos theta in
  let st = Float.sin theta in
  ( cx + Float.iround_nearest_exn ((lx *. ct) -. (ly *. st))
  , cy + Float.iround_nearest_exn ((lx *. st) +. (ly *. ct)) )
;;

let tree_cluster ~x ~y ~size ~base =
  let cx = x + (size / 2) in
  let trunk_w = Int.max 2 (size / 6) in
  let trunk =
    Prim.Fill_rect
      { x = cx - (trunk_w / 2)
      ; y
      ; w = trunk_w
      ; h = size / 2
      ; color = trunk_wood
      }
  in
  let leaf dx dy r color =
    Prim.Fill_ellipse
      { x = cx + dx; y = y + dy; rx = Int.max 1 r; ry = Int.max 1 r; color }
  in
  (* Back-to-front: darker, lower discs first; bright crown last. *)
  [ trunk
  ; leaf 0 (size / 2) (size / 3) (Color.darken base ~frac:0.16)
  ; leaf (-size / 4) (2 * size / 3) (size / 4) base
  ; leaf (size / 4) (2 * size / 3) (size / 4) (Color.darken base ~frac:0.08)
  ; leaf 0 (3 * size / 4) (size / 5) (Color.lighten base ~frac:0.16)
  ; leaf
      (-size / 8)
      (5 * size / 6)
      (size / 8)
      (Color.lighten base ~frac:0.24)
  ]
;;

let brick_wall ~x ~y ~size ~base =
  let mortar = Color.darken base ~frac:0.28 in
  let fill = Prim.Fill_rect { x; y; w = size; h = size; color = base } in
  let courses = 3 in
  let course_h = size / courses in
  let seam i =
    let ly = y + (i * course_h) in
    Prim.Line
      { x1 = x; y1 = ly; x2 = x + size; y2 = ly; width = 1; color = mortar }
  in
  let joint course frac =
    let ly = y + (course * course_h) in
    let lx = x + Float.iround_nearest_exn (Float.of_int size *. frac) in
    Prim.Line
      { x1 = lx
      ; y1 = ly
      ; x2 = lx
      ; y2 = ly + course_h
      ; width = 1
      ; color = mortar
      }
  in
  (* Two horizontal courses, then vertical joints staggered course to course. *)
  [ fill
  ; seam 1
  ; seam 2
  ; joint 0 0.5
  ; joint 1 0.25
  ; joint 1 0.75
  ; joint 2 0.5
  ]
;;

let rock_wall ~x ~y ~size ~base =
  let fill = Prim.Fill_rect { x; y; w = size; h = size; color = base } in
  let facet points color = Prim.Fill_poly { points; color } in
  let speck dx dy r color =
    Prim.Fill_ellipse
      { x = x + dx; y = y + dy; rx = Int.max 1 r; ry = Int.max 1 r; color }
  in
  [ fill
  ; facet
      [| x, y + size
       ; x + (size / 2), y + (3 * size / 4)
       ; x + (size / 3), y + (size / 3)
       ; x, y + (size / 4)
      |]
      (Color.lighten base ~frac:0.12)
  ; facet
      [| x + size, y
       ; x + (size / 2), y + (size / 4)
       ; x + (2 * size / 3), y + (2 * size / 3)
       ; x + size, y + (3 * size / 4)
      |]
      (Color.darken base ~frac:0.16)
  ; speck (size / 4) (size / 3) (size / 12) (Color.lighten base ~frac:0.2)
  ; speck
      (3 * size / 4)
      (3 * size / 5)
      (size / 14)
      (Color.darken base ~frac:0.22)
  ; speck (size / 2) (size / 6) (size / 16) (Color.lighten base ~frac:0.14)
  ]
;;

let plank_floor ~x ~y ~size ~base =
  let seam_color = Color.darken base ~frac:0.24 in
  let grain_color = Color.darken base ~frac:0.12 in
  let fill = Prim.Fill_rect { x; y; w = size; h = size; color = base } in
  let planks = 4 in
  let plank_h = size / planks in
  let seam i =
    let ly = y + (i * plank_h) in
    Prim.Line
      { x1 = x
      ; y1 = ly
      ; x2 = x + size
      ; y2 = ly
      ; width = 1
      ; color = seam_color
      }
  in
  let grain plank frac =
    let ly = y + (plank * plank_h) + (plank_h / 2) in
    let lx = x + Float.iround_nearest_exn (Float.of_int size *. frac) in
    Prim.Line
      { x1 = lx
      ; y1 = ly
      ; x2 = lx + (size / 6)
      ; y2 = ly
      ; width = 1
      ; color = grain_color
      }
  in
  (fill :: List.map [ 1; 2; 3 ] ~f:seam)
  @ [ grain 0 0.3; grain 1 0.6; grain 2 0.2; grain 3 0.7 ]
;;

let car_sprite ~cx ~cy ~size ~heading ~livery ~number =
  let theta = heading in
  let sf = Float.of_int size in
  let hl = sf *. 0.42 in
  let hw = sf *. 0.26 in
  let corner lx ly = rotate ~cx ~cy ~theta (lx, ly) in
  let shadow =
    Prim.Fill_ellipse
      { x = cx
      ; y = cy - (size / 8)
      ; rx = Int.max 2 (size * 2 / 5)
      ; ry = Int.max 1 (size / 6)
      ; color = Palette.car_shadow
      }
  in
  (* A wheel is a short rect, rotated with the body, sitting at a body
     corner. *)
  let wheel wx wy =
    let wl = sf *. 0.16 in
    let ww = sf *. 0.09 in
    Prim.Fill_poly
      { points =
          [| corner (wx +. wl) (wy +. ww)
           ; corner (wx +. wl) (wy -. ww)
           ; corner (wx -. wl) (wy -. ww)
           ; corner (wx -. wl) (wy +. ww)
          |]
      ; color = wheel_rubber
      }
  in
  let wheels =
    [ wheel (hl *. 0.55) (hw *. 1.05)
    ; wheel (hl *. 0.55) (-.hw *. 1.05)
    ; wheel (-.hl *. 0.55) (hw *. 1.05)
    ; wheel (-.hl *. 0.55) (-.hw *. 1.05)
    ]
  in
  (* A tapered body: the nose (+x) narrows, so orientation reads even small. *)
  let body =
    Prim.Fill_poly
      { points =
          [| corner hl (hw *. 0.6)
           ; corner (hl *. 0.5) hw
           ; corner (-.hl *. 0.85) hw
           ; corner (-.hl) (hw *. 0.7)
           ; corner (-.hl) (-.hw *. 0.7)
           ; corner (-.hl *. 0.85) (-.hw)
           ; corner (hl *. 0.5) (-.hw)
           ; corner hl (-.hw *. 0.6)
          |]
      ; color = livery
      }
  in
  let windshield =
    Prim.Fill_poly
      { points =
          [| corner (hl *. 0.5) (hw *. 0.6)
           ; corner (hl *. 0.1) (hw *. 0.6)
           ; corner (hl *. 0.1) (-.hw *. 0.6)
           ; corner (hl *. 0.5) (-.hw *. 0.6)
          |]
      ; color = windshield_glass
      }
  in
  let headlight lx ly =
    let hx, hy = corner lx ly in
    Prim.Fill_ellipse
      { x = hx
      ; y = hy
      ; rx = Int.max 1 (size / 12)
      ; ry = Int.max 1 (size / 12)
      ; color = headlight_glow
      }
  in
  let number_prims =
    match number with
    | None -> []
    | Some n ->
      [ Prim.Text
          { x = cx - (size / 8)
          ; y = cy - (size / 6)
          ; s = Int.to_string n
          ; size = `Small
          ; color = number_ink
          }
      ]
  in
  ([ shadow ] @ wheels)
  @ [ body
    ; windshield
    ; headlight (hl *. 0.92) (hw *. 0.55)
    ; headlight (hl *. 0.92) (-.hw *. 0.55)
    ]
  @ number_prims
;;

let banner ~x ~y ~size ~color =
  let pole_x = x + (size / 4) in
  let pole =
    Prim.Line
      { x1 = pole_x
      ; y1 = y
      ; x2 = pole_x
      ; y2 = y + size
      ; width = Int.max 1 (size / 16)
      ; color = pole_wood
      }
  in
  let flag_top = y + size in
  let flag_bot = y + (size / 2) in
  let flag_right = x + (3 * size / 4) in
  let flag =
    Prim.Fill_poly
      { points =
          [| pole_x, flag_top
           ; flag_right, flag_top - (size / 8)
           ; flag_right - (size / 6), (flag_top + flag_bot) / 2
             (* swallowtail notch *)
           ; flag_right, flag_bot + (size / 8)
           ; pole_x, flag_bot
          |]
      ; color
      }
  in
  let trim =
    Prim.Line
      { x1 = pole_x
      ; y1 = flag_bot
      ; x2 = flag_right
      ; y2 = flag_bot + (size / 8)
      ; width = 1
      ; color = Color.darken color ~frac:0.3
      }
  in
  let pennant =
    Prim.Fill_poly
      { points =
          [| pole_x, y + size
           ; pole_x + (size / 6), y + size - (size / 12)
           ; pole_x, y + size - (size / 6)
          |]
      ; color = Color.lighten color ~frac:0.2
      }
  in
  [ pole; flag; trim; pennant ]
;;

let rune_crystal ~x ~y ~size =
  let cx = x + (size / 2) in
  let glow =
    Prim.Fill_ellipse
      { x = cx
      ; y = y + (size / 2)
      ; rx = Int.max 2 (size * 2 / 5)
      ; ry = Int.max 2 (size * 2 / 5)
      ; color = Color.darken Palette.ice ~frac:0.32
      }
  in
  let diamond dcx dcy w h color =
    Prim.Fill_poly
      { points = [| dcx, dcy + h; dcx + w, dcy; dcx, dcy - h; dcx - w, dcy |]
      ; color
      }
  in
  let shine ax ay bx by =
    Prim.Line
      { x1 = ax
      ; y1 = ay
      ; x2 = bx
      ; y2 = by
      ; width = 1
      ; color = Palette.ice_shine
      }
  in
  [ glow
  ; diamond
      (cx - (size / 5))
      (y + (size / 3))
      (Int.max 2 (size / 8))
      (Int.max 2 (size / 5))
      (Color.darken Palette.ice ~frac:0.12)
  ; diamond
      (cx + (size / 5))
      (y + (2 * size / 5))
      (Int.max 2 (size / 9))
      (Int.max 2 (size / 6))
      (Color.lighten Palette.ice ~frac:0.1)
  ; diamond
      cx
      (y + (size / 2))
      (Int.max 2 (size / 5))
      (Int.max 2 (size / 3))
      Palette.ice
  ; shine
      cx
      (y + (size / 2) + (size / 6))
      (cx + (size / 12))
      (y + (size / 2) + (size / 3))
  ; shine (cx - (size / 12)) (y + (size / 2)) cx (y + (size / 2) + (size / 8))
  ]
;;

module Minimap = struct
  let border_tint = Color.lighten Palette.bezel ~frac:0.4

  let render map track ~cars ~x ~y ~w ~h =
    let cols = Game_map.cols map in
    let rows = Game_map.rows map in
    let cell_size = Game_map.cell_size map in
    (* Largest integer cell that fits the box in both axes; then center. *)
    let cs = Int.max 1 (Int.min (w / Int.max 1 cols) (h / Int.max 1 rows)) in
    let used_w = cs * cols in
    let used_h = cs * rows in
    let ox = x + ((w - used_w) / 2) in
    let oy = y + ((h - used_h) / 2) in
    let out = Queue.create () in
    let add p = Queue.enqueue out p in
    for row = 0 to rows - 1 do
      for col = 0 to cols - 1 do
        let cell = { Cell.col; row } in
        let environment = Game_map.environment_at map cell in
        let center = Cell.center cell ~cell_size in
        let surface = Map_state.surface_at track ~map center in
        let color = Palette.ground ~surface ~environment in
        add
          (Prim.Fill_rect
             { x = ox + (col * cs)
             ; y = oy + (row * cs)
             ; w = cs
             ; h = cs
             ; color
             })
      done
    done;
    List.iter cars ~f:(fun (pos, team) ->
      let fx =
        Float.of_int ox +. (pos.Position.x /. cell_size *. Float.of_int cs)
      in
      let fy =
        Float.of_int oy +. (pos.Position.y /. cell_size *. Float.of_int cs)
      in
      let dot_r = Int.max 1 (cs / 2) in
      add
        (Prim.Fill_ellipse
           { x = Float.iround_nearest_exn fx
           ; y = Float.iround_nearest_exn fy
           ; rx = dot_r
           ; ry = dot_r
           ; color = Palette.team team
           }));
    add
      (Prim.Rect
         { x = ox; y = oy; w = used_w; h = used_h; color = border_tint });
    Queue.to_list out
  ;;
end
