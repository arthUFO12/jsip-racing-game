open! Core
open Racing_types
module Prim = Jsip_client_render.Prim
module Palette = Jsip_client_render.Palette
module Color = Prim.Color

(* Colours the shared {!Palette} doesn't name. Kept local (spec: don't grow
   Palette) — glyph inks for the item tiles, the dim countdown scrim, and the
   mud-bomb brown for effect chips. *)
let scrim = Color.rgb 8 8 12
let magic_flame = Color.rgb 226 74 40
let light_beam = Color.rgb 250 240 150
let axe_steel = Color.rgb 184 190 200
let wood_brown = Color.rgb 120 78 42
let mud_brown = Color.rgb 120 82 46

(* Rough pixel widths per glyph size. [Prim.Text] is fixed-size, so centering
   text means guessing its footprint; these match the backend's 18px/12px
   fonts closely enough for layout. *)
let large_char_px = 11
let small_char_px = 7

let ordinal n =
  (* Ints only, so a wildcard tail is fine (the no-wildcard rule is for
     variants). Mirrors {!Render.ordinal}. *)
  let suffix =
    match n % 100 with
    | 11 | 12 | 13 -> "th"
    | _ ->
      (match n % 10 with 1 -> "st" | 2 -> "nd" | 3 -> "rd" | _ -> "th")
  in
  sprintf "%d%s" n suffix
;;

(* --- countdown --- *)

let countdown ~count ~window_w ~window_h =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  add
    (Prim.Fill_rect
       { x = 0; y = 0; w = window_w; h = window_h; color = scrim });
  let cx = window_w / 2 in
  let cy = window_h / 2 in
  let radius = Int.max 40 (Int.min window_w window_h / 5) in
  let thickness = Int.max 6 (radius / 5) in
  (* An accent ring: a filled disc with the scrim punched back out of it. *)
  add
    (Prim.Fill_ellipse
       { x = cx
       ; y = cy
       ; rx = radius
       ; ry = radius
       ; color = Palette.hud_accent
       });
  add
    (Prim.Fill_ellipse
       { x = cx
       ; y = cy
       ; rx = radius - thickness
       ; ry = radius - thickness
       ; color = scrim
       });
  let label, label_color =
    if count = 0
    then "GO!", Palette.hud_accent
    else Int.to_string count, Palette.hud_title
  in
  let text_x = cx - (String.length label * large_char_px / 2) in
  let text_y = cy - 9 in
  add
    (Prim.Text
       { x = text_x
       ; y = text_y
       ; s = label
       ; size = `Large
       ; color = label_color
       });
  Queue.to_list out
;;

(* --- standings --- *)

module Standing = struct
  type t =
    { place : int
    ; name : string
    ; team : Team_id.t
    ; laps : int
    }
  [@@deriving sexp_of]
end

let by_place =
  List.sort ~compare:(fun a b ->
    Int.compare a.Standing.place b.Standing.place)
;;

let swatch ~add ~x ~y ~size ~team =
  add
    (Prim.Fill_rect { x; y; w = size; h = size; color = Palette.team team });
  add (Prim.Rect { x; y; w = size; h = size; color = Palette.hud_border })
;;

let finish_board standings ~window_w ~window_h =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  add
    (Prim.Fill_rect
       { x = 0
       ; y = 0
       ; w = window_w
       ; h = window_h
       ; color = Palette.hud_panel
       });
  add
    (Prim.Rect
       { x = 0
       ; y = 0
       ; w = window_w
       ; h = window_h
       ; color = Palette.hud_border
       });
  let title = "FINISH" in
  let title_x = (window_w / 2) - (String.length title * large_char_px / 2) in
  let title_y = window_h - 70 in
  add
    (Prim.Text
       { x = title_x
       ; y = title_y
       ; s = title
       ; size = `Large
       ; color = Palette.hud_title
       });
  let row_h = 40 in
  let first_row_y = title_y - 60 in
  let left_x = (window_w / 2) - 200 in
  let swatch_size = 20 in
  List.iteri
    (by_place standings)
    ~f:(fun i { Standing.place; name; team; laps } ->
      let y = first_row_y - (i * row_h) in
      let is_winner = place = 1 in
      let text_color =
        if is_winner then Palette.hud_accent else Palette.hud_text
      in
      if is_winner
      then
        add
          (Prim.Fill_rect
             { x = left_x - 12
             ; y = y - 8
             ; w = 424
             ; h = row_h - 6
             ; color = Color.darken Palette.hud_accent ~frac:0.7
             });
      add
        (Prim.Text
           { x = left_x
           ; y
           ; s = ordinal place
           ; size = `Large
           ; color = text_color
           });
      swatch ~add ~x:(left_x + 70) ~y ~size:swatch_size ~team;
      add
        (Prim.Text
           { x = left_x + 100
           ; y
           ; s = name
           ; size = `Large
           ; color = text_color
           });
      add
        (Prim.Text
           { x = left_x + 300
           ; y
           ; s = sprintf "%d laps" laps
           ; size = `Large
           ; color = text_color
           }));
  Queue.to_list out
;;

let truncate_name name ~max_len =
  if String.length name <= max_len
  then name
  else String.prefix name (max_len - 1) ^ "."
;;

let leaderboard standings ~x ~y =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  let sorted = by_place standings in
  let row_h = 22 in
  let pad = 6 in
  let width = 180 in
  let height = (List.length sorted * row_h) + (2 * pad) in
  (* Anchor is the top-left; the panel and rows extend downward from [y]. *)
  add
    (Prim.Fill_rect
       { x
       ; y = y - height
       ; w = width
       ; h = height
       ; color = Color.darken Palette.hud_panel ~frac:0.1
       });
  add
    (Prim.Rect
       { x
       ; y = y - height
       ; w = width
       ; h = height
       ; color = Palette.hud_border
       });
  let swatch_size = 12 in
  List.iteri sorted ~f:(fun i { Standing.place; name; team; laps } ->
    let row_top = y - pad - (i * row_h) in
    let text_y = row_top - 14 in
    add
      (Prim.Text
         { x = x + 6
         ; y = text_y
         ; s = ordinal place
         ; size = `Small
         ; color = Palette.hud_text
         });
    swatch ~add ~x:(x + 42) ~y:(text_y - 1) ~size:swatch_size ~team;
    add
      (Prim.Text
         { x = x + 60
         ; y = text_y
         ; s = truncate_name name ~max_len:12
         ; size = `Small
         ; color = Palette.hud_text
         });
    add
      (Prim.Text
         { x = x + 148
         ; y = text_y
         ; s = sprintf "L%d" laps
         ; size = `Small
         ; color = Palette.hud_text
         }));
  Queue.to_list out
;;

(* --- inventory --- *)

(* A distinct, recognisable glyph per powerup, drawn inside the tile whose
   bottom-left is [(tx, y)] and side is [size]. Enumerated in full: a new
   powerup must choose an icon here before it compiles. *)
let draw_glyph ~add ~(powerup : Powerup.t) ~tx ~y ~size =
  let cx = tx + (size / 2) in
  let cy = y + (size / 2) in
  match powerup with
  | Speed_boost ->
    let chevron ox =
      add
        (Prim.Line
           { x1 = ox
           ; y1 = y + (size * 3 / 4)
           ; x2 = ox + (size / 6)
           ; y2 = cy
           ; width = 3
           ; color = Palette.boost_flame
           });
      add
        (Prim.Line
           { x1 = ox + (size / 6)
           ; y1 = cy
           ; x2 = ox
           ; y2 = y + (size / 4)
           ; width = 3
           ; color = Palette.boost_flame
           })
    in
    chevron (tx + (size / 3));
    chevron (tx + (size / 2))
  | Invincibility ->
    add
      (Prim.Fill_poly
         { points =
             [| cx - (size / 4), y + (size * 3 / 4)
              ; cx + (size / 4), y + (size * 3 / 4)
              ; cx + (size / 4), y + (2 * size / 5)
              ; cx, y + (size / 5)
              ; cx - (size / 4), y + (2 * size / 5)
             |]
         ; color = Palette.shield
         })
  | Glider ->
    add
      (Prim.Fill_poly
         { points =
             [| tx + (size / 6), cy
              ; tx + (size * 5 / 6), y + (size * 3 / 4)
              ; tx + (size * 5 / 6), cy - (size / 8)
             |]
         ; color = Palette.glider_wing
         })
  | Flame_magic ->
    add
      (Prim.Fill_poly
         { points =
             [| cx, y + (size * 4 / 5)
              ; cx + (size / 5), cy
              ; cx, y + (size / 5)
              ; cx - (size / 5), cy
             |]
         ; color = magic_flame
         })
  | Flashlight ->
    (* body plus a spreading cone of light *)
    add
      (Prim.Fill_rect
         { x = tx + (size / 6)
         ; y = cy - (size / 10)
         ; w = size / 8
         ; h = size / 5
         ; color = Palette.hud_border
         });
    add
      (Prim.Fill_poly
         { points =
             [| tx + (size / 4), cy + (size / 12)
              ; tx + (size * 5 / 6), y + (size * 3 / 4)
              ; tx + (size * 5 / 6), y + (size / 4)
              ; tx + (size / 4), cy - (size / 12)
             |]
         ; color = light_beam
         })
  | Axe ->
    add
      (Prim.Line
         { x1 = tx + (size / 3)
         ; y1 = y + (size / 5)
         ; x2 = tx + (2 * size / 3)
         ; y2 = y + (4 * size / 5)
         ; width = 3
         ; color = wood_brown
         });
    add
      (Prim.Fill_poly
         { points =
             [| cx, y + (3 * size / 5)
              ; tx + (4 * size / 5), y + (4 * size / 5)
              ; tx + (5 * size / 6), y + (3 * size / 5)
              ; tx + (3 * size / 5), y + (2 * size / 5)
             |]
         ; color = axe_steel
         })
;;

let inventory_bar items ~x ~y =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  let tile = 34 in
  let gap = 6 in
  List.iteri items ~f:(fun i (powerup, count) ->
    let tx = x + (i * (tile + gap)) in
    add
      (Prim.Fill_rect
         { x = tx
         ; y
         ; w = tile
         ; h = tile
         ; color = Color.darken Palette.hud_panel ~frac:0.08
         });
    add
      (Prim.Rect
         { x = tx; y; w = tile; h = tile; color = Palette.hud_border });
    draw_glyph ~add ~powerup ~tx ~y ~size:tile;
    add
      (Prim.Text
         { x = tx + 3
         ; y = y + 3
         ; s = sprintf "x%d" count
         ; size = `Small
         ; color = Palette.hud_text
         }));
  Queue.to_list out
;;

(* --- effect chips --- *)

let powerup_label (powerup : Powerup.t) =
  match powerup with
  | Speed_boost -> "Boost"
  | Invincibility -> "Shield"
  | Glider -> "Glide"
  | Flame_magic -> "Flame"
  | Flashlight -> "Light"
  | Axe -> "Axe"
;;

let powerup_color (powerup : Powerup.t) =
  match powerup with
  | Speed_boost -> Palette.boost_flame
  | Invincibility -> Palette.shield
  | Glider -> Palette.glider_wing
  | Flame_magic -> magic_flame
  | Flashlight -> light_beam
  | Axe -> axe_steel
;;

let kind_label_color (kind : Effect.Kind.t) =
  match kind with
  | Powerup powerup -> powerup_label powerup, powerup_color powerup
  | Vines -> "Vines", Palette.vines
  | Mud_bomb -> "Mud", mud_brown
;;

let effect_chips effects ~x ~y =
  let out = Queue.create () in
  let add p = Queue.enqueue out p in
  let height = 22 in
  let gap = 6 in
  let (_ : int) =
    List.fold effects ~init:x ~f:(fun chip_x { Effect.kind; remaining } ->
      let label, color = kind_label_color kind in
      let secs = Int.of_float (Time_ns.Span.to_sec remaining) in
      let text = sprintf "%s %ds" label secs in
      let width = 12 + (String.length text * small_char_px) in
      add
        (Prim.Fill_rect
           { x = chip_x
           ; y
           ; w = width
           ; h = height
           ; color = Color.darken color ~frac:0.4
           });
      add (Prim.Rect { x = chip_x; y; w = width; h = height; color });
      add
        (Prim.Text
           { x = chip_x + 6
           ; y = y + 6
           ; s = text
           ; size = `Small
           ; color = Palette.hud_title
           });
      chip_x + width + gap)
  in
  Queue.to_list out
;;
