open! Core

type t =
  { name : string
  ; laps_to_win : int
  ; cell_size : float
  ; surfaces : Surface.t array array
      (* [surfaces.(row).(col)]; row 0 is the BOTTOM row (y-up). Map files
         list rows top-first for readability; [load] flips them. *)
  ; environments : Environment.t array array
  ; checkpoints : Checkpoint.t array
  ; start_grid : Pose.t list
  ; initial_features : Feature.t list
  }
[@@deriving sexp_of, bin_io]

(* Expected shape of the implementation:
   1. Define an internal [Spec] module deriving [of_sexp] that mirrors the
      authoring schema in doc/map-design.md (grids as row lists, top row
      first; features as kind + cells, with no ids and no phases).
   2. Parse with [Or_error.try_with] around [Spec.t_of_sexp].
   3. Validate every invariant listed in the .mli, collecting ALL errors with
      context ([Or_error.combine_errors_unit]), not just the first.
   4. Build [t]: flip the row order, assign [Feature_id.t]s in listing order,
      and wrap feature params in their rest phases ([Intact], [Open],
      [Hanging]). *)
let load (_ : Sexp.t) = failwith "TODO: implement Game_map.load"

let load_file_exn filename =
  In_channel.read_all filename |> Sexp.of_string |> load |> Or_error.ok_exn
;;

let name t = t.name
let laps_to_win t = t.laps_to_win
let cell_size t = t.cell_size
let rows t = Array.length t.surfaces

let cols t =
  match Array.length t.surfaces with
  | 0 -> 0
  | _ -> Array.length t.surfaces.(0)
;;

let is_in_bounds t (cell : Cell.t) =
  cell.row >= 0 && cell.row < rows t && cell.col >= 0 && cell.col < cols t
;;

let base_surface_at t (cell : Cell.t) =
  match is_in_bounds t cell with
  | true -> t.surfaces.(cell.row).(cell.col)
  | false -> Surface.Wall
;;

let environment_at t (cell : Cell.t) =
  match is_in_bounds t cell with
  | true -> t.environments.(cell.row).(cell.col)
  | false -> Environment.Forest
;;

let cell_at t position = Cell.of_position position ~cell_size:t.cell_size
let checkpoints t = t.checkpoints

let checkpoint_at t cell =
  Array.find_map t.checkpoints ~f:(fun (checkpoint : Checkpoint.t) ->
    match List.mem checkpoint.cells cell ~equal:Cell.equal with
    | true -> Some checkpoint.index
    | false -> None)
;;

let start_grid t = t.start_grid
let initial_features t = t.initial_features
