open! Core
open Racing_map
open Racing_types
module Color = Prim.Color

let ground ~(surface : Surface.t) ~(environment : Environment.t) =
  (* Environment sets the mood; surface sets the material within it. Fully
     enumerated on purpose (no catch-all): a new surface or zone must make a
     colour choice here before it compiles. *)
  match environment, surface with
  | Forest, Road -> Color.rgb 184 142 92 (* packed dirt *)
  | Forest, Trees -> Color.rgb 61 107 47 (* the tree line *)
  | Forest, Wall -> Color.rgb 107 100 94 (* mossy boulder *)
  | Castle, Road -> Color.rgb 156 150 146 (* flagstone *)
  | Castle, Trees -> Color.rgb 70 96 58
  | Castle, Wall -> Color.rgb 104 98 112 (* cool cut stone *)
  | Cave, Road -> Color.rgb 92 86 98 (* damp rock path *)
  | Cave, Trees -> Color.rgb 46 68 42 (* cave moss *)
  | Cave, Wall -> Color.rgb 45 42 54 (* near-black rock *)
;;

let team_liveries =
  [| Color.rgb 200 58 46 (* red *)
   ; Color.rgb 46 107 200 (* blue *)
   ; Color.rgb 224 176 40 (* gold *)
   ; Color.rgb 58 168 74 (* green *)
   ; Color.rgb 138 58 184 (* purple *)
   ; Color.rgb 224 122 40 (* orange *)
  |]
;;

let team id =
  let n = Array.length team_liveries in
  team_liveries.(Int.( % ) (Team_id.to_int id) n)
;;

let water = Color.rgb 46 107 158
let water_highlight = Color.rgb 120 186 224
let bridge_plank = Color.rgb 138 92 48
let gate_iron = Color.rgb 58 54 48
let gate_bar = Color.rgb 96 90 80
let stalactite = Color.rgb 122 116 128
let debris = Color.rgb 107 95 82
let ice = Color.rgb 150 214 232
let ice_shine = Color.rgb 232 252 255
let telegraph = Color.rgb 236 176 44
let danger = Color.rgb 208 62 42
let boost_flame = Color.rgb 250 168 44
let glider_wing = Color.rgb 220 232 244
let shield = Color.rgb 246 224 120
let vines = Color.rgb 74 138 52
let bezel = Color.rgb 22 18 14
let car_shadow = Color.rgb 20 16 12
let cave_shade = Color.rgb 12 10 22
let hud_panel = Color.rgb 34 28 24
let hud_border = Color.rgb 12 10 8
let hud_text = Color.rgb 232 192 96
let hud_title = Color.rgb 239 230 208
let hud_accent = Color.rgb 244 202 72
