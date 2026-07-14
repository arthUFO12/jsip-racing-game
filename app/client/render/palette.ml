open! Core
open Racing_map
open Racing_types
module Color = Prim.Color

let ground ~(surface : Surface.t) ~(environment : Environment.t) =
  (* Environment sets the mood; surface sets the material within it. Fully
     enumerated on purpose (no catch-all): a new surface or zone must make a
     colour choice here before it compiles.

     The values are tuned as a set, not one at a time: within each zone the
     drivable [Road] is the lightest surface so it reads as the path, [Wall]
     sits a notch darker, and [Trees] carry the zone's green. Everything is
     slightly desaturated so the brighter feature and car colours can pop. *)
  match environment, surface with
  | Forest, Road -> Color.rgb 182 146 100 (* packed dirt *)
  | Forest, Trees -> Color.rgb 76 114 62 (* the tree line *)
  | Forest, Wall -> Color.rgb 124 118 108 (* mossy boulder *)
  | Castle, Road -> Color.rgb 162 158 152 (* flagstone *)
  | Castle, Trees -> Color.rgb 78 104 66
  | Castle, Wall -> Color.rgb 116 112 128 (* cool cut stone *)
  | Cave, Road -> Color.rgb 98 92 106 (* damp rock path *)
  | Cave, Trees -> Color.rgb 54 78 50 (* cave moss *)
  | Cave, Wall -> Color.rgb 46 44 56 (* near-black rock *)
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

let water = Color.rgb 42 104 156
let water_highlight = Color.rgb 126 190 226
let bridge_plank = Color.rgb 146 98 54
let gate_iron = Color.rgb 58 54 48
let gate_bar = Color.rgb 104 98 86
let stalactite = Color.rgb 126 120 132
let debris = Color.rgb 110 98 84
let ice = Color.rgb 150 214 232
let ice_shine = Color.rgb 234 252 255
let telegraph = Color.rgb 238 180 48
let danger = Color.rgb 210 62 42
let boost_flame = Color.rgb 250 168 44
let glider_wing = Color.rgb 220 232 244
let shield = Color.rgb 246 224 120
let vines = Color.rgb 74 138 52
let bezel = Color.rgb 22 18 14
let car_shadow = Color.rgb 18 14 12
let cave_shade = Color.rgb 12 10 22
let hud_panel = Color.rgb 38 31 26
let hud_border = Color.rgb 12 10 8
let hud_shadow = Color.rgb 6 5 8
let hud_text = Color.rgb 232 192 96
let hud_title = Color.rgb 240 231 210
let hud_accent = Color.rgb 244 202 72
let rim_light = Color.rgb 250 246 232
