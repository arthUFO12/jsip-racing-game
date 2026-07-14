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

(* The authoring schema (doc/map-design.md): grids are row lists written
   TOP row first (human reading order); features are kind + footprint,
   with no ids and no phases. *)
module Spec = struct
  module Feature_spec = struct
    type t =
      { kind : Feature.Kind.t
      ; cells : Cell.t list
      }
    [@@deriving of_sexp]
  end

  type t =
    { name : string
    ; laps_to_win : int
    ; cell_size : float
    ; surfaces : Surface.t list list
    ; environments : Environment.t list list
    ; checkpoints : Checkpoint.t list
    ; start_grid : Pose.t list
    ; features : Feature_spec.t list
    }
  [@@deriving of_sexp]
end

(* Rows are listed top-first in the file; internally row 0 is the BOTTOM
   row, so reverse while converting. *)
let grid_of_rows rows = Array.of_list_rev (List.map rows ~f:Array.of_list)

let in_grid (cell : Cell.t) ~rows ~cols =
  cell.row >= 0 && cell.row < rows && cell.col >= 0 && cell.col < cols
;;

let sorted_checkpoints checkpoints =
  List.sort checkpoints ~compare:(fun (a : Checkpoint.t) (b : Checkpoint.t) ->
    Int.compare a.index b.index)
;;

(* {2 Shape checks}

   Everything that must hold before the semantic checks below can index
   the grids and pair up checkpoints without crashing. Each check returns
   a (possibly empty) list of errors so [load] can report ALL problems at
   once. *)

let grid_shape_errors ~grid_name grid =
  match grid with
  | [] ->
    [ Or_error.error_s [%message "grid must be nonempty" (grid_name : string)] ]
  | first_row :: _ ->
    let expected_cols = List.length first_row in
    List.filter_mapi grid ~f:(fun row_from_top row ->
      let row_length = List.length row in
      match row_length = expected_cols && row_length > 0 with
      | true -> None
      | false ->
        Some
          (Or_error.error_s
             [%message
               "grid rows must all have the same nonzero length"
                 (grid_name : string)
                 (row_from_top : int)
                 (row_length : int)
                 (expected_cols : int)]))
;;

let grid_dims_errors ~surfaces ~environments =
  let surface_rows = List.length surfaces in
  let environment_rows = List.length environments in
  let row_count_errors =
    match surface_rows = environment_rows with
    | true -> []
    | false ->
      [ Or_error.error_s
          [%message
            "environments grid must have the same dimensions as surfaces"
              (surface_rows : int)
              (environment_rows : int)]
      ]
  in
  let col_count_errors =
    match surfaces, environments with
    | [], _ | _, [] -> [] (* emptiness reported by [grid_shape_errors] *)
    | surface_row :: _, environment_row :: _ ->
      let surface_cols = List.length surface_row in
      let environment_cols = List.length environment_row in
      (match surface_cols = environment_cols with
       | true -> []
       | false ->
         [ Or_error.error_s
             [%message
               "environments grid must have the same dimensions as surfaces"
                 (surface_cols : int)
                 (environment_cols : int)]
         ])
  in
  row_count_errors @ col_count_errors
;;

let checkpoint_index_errors (checkpoints : Checkpoint.t list) =
  let indexes =
    List.map checkpoints ~f:(fun (checkpoint : Checkpoint.t) -> checkpoint.index)
    |> List.sort ~compare:Int.compare
  in
  let checkpoint_count = List.length indexes in
  let count_errors =
    match checkpoint_count >= 2 with
    | true -> []
    | false ->
      [ Or_error.error_s
          [%message
            "map needs at least two checkpoints" (checkpoint_count : int)]
      ]
  in
  let index_errors =
    match List.equal Int.equal indexes (List.init checkpoint_count ~f:Fn.id) with
    | true -> []
    | false ->
      [ Or_error.error_s
          [%message
            "checkpoint indexes must be exactly 0 .. n-1 (no duplicates or gaps)"
              (indexes : int list)]
      ]
  in
  count_errors @ index_errors
;;

let checkpoint_cell_shape_errors (checkpoints : Checkpoint.t list) ~rows ~cols =
  List.concat_map checkpoints ~f:(fun (checkpoint : Checkpoint.t) ->
    let index = checkpoint.index in
    let empty_errors =
      match checkpoint.cells with
      | _ :: _ -> []
      | [] ->
        [ Or_error.error_s [%message "checkpoint has no cells" (index : int)] ]
    in
    let bounds_errors =
      List.filter_map checkpoint.cells ~f:(fun cell ->
        match in_grid cell ~rows ~cols with
        | true -> None
        | false ->
          Some
            (Or_error.error_s
               [%message
                 "checkpoint cell is out of bounds"
                   (index : int)
                   (cell : Cell.t)
                   (rows : int)
                   (cols : int)]))
    in
    empty_errors @ bounds_errors)
;;

let feature_shape_errors (features : Spec.Feature_spec.t list) ~rows ~cols =
  List.concat_mapi features ~f:(fun feature_index (feature : Spec.Feature_spec.t) ->
    let kind = feature.kind in
    let empty_errors =
      match feature.cells with
      | _ :: _ -> []
      | [] ->
        [ Or_error.error_s
            [%message
              "feature footprint must be nonempty"
                (feature_index : int)
                (kind : Feature.Kind.t)]
        ]
    in
    let bounds_errors =
      List.filter_map feature.cells ~f:(fun cell ->
        match in_grid cell ~rows ~cols with
        | true -> None
        | false ->
          Some
            (Or_error.error_s
               [%message
                 "feature cell is out of bounds"
                   (feature_index : int)
                   (kind : Feature.Kind.t)
                   (cell : Cell.t)
                   (rows : int)
                   (cols : int)]))
    in
    empty_errors @ bounds_errors)
;;

let shape_errors (spec : Spec.t) ~rows ~cols =
  let scalar_errors =
    [ (match spec.laps_to_win >= 1 with
       | true -> Ok ()
       | false ->
         Or_error.error_s
           [%message
             "laps_to_win must be at least 1"
               ~laps_to_win:(spec.laps_to_win : int)])
    ; (match Float.(spec.cell_size > 0.) with
       | true -> Ok ()
       | false ->
         Or_error.error_s
           [%message
             "cell_size must be positive" ~cell_size:(spec.cell_size : float)])
    ; (match spec.start_grid with
       | _ :: _ -> Ok ()
       | [] -> Or_error.error_s [%message "start_grid must be nonempty"])
    ]
  in
  scalar_errors
  @ grid_shape_errors ~grid_name:"surfaces" spec.surfaces
  @ grid_shape_errors ~grid_name:"environments" spec.environments
  @ grid_dims_errors ~surfaces:spec.surfaces ~environments:spec.environments
  @ checkpoint_index_errors spec.checkpoints
  @ checkpoint_cell_shape_errors spec.checkpoints ~rows ~cols
  @ feature_shape_errors spec.features ~rows ~cols
;;

(* {2 Semantic checks}

   Only run once the shape checks pass, so grid indexing, checkpoint
   pairing, and [Cell.of_vec2] are all safe. [surfaces]/[environments]
   are the flipped internal arrays (row 0 = bottom). *)

let semantic_errors (spec : Spec.t) ~surfaces ~environments ~rows ~cols =
  let surface_at (cell : Cell.t) =
    match in_grid cell ~rows ~cols with
    | true -> surfaces.(cell.row).(cell.col)
    | false -> Surface.Wall
  in
  let environment_at (cell : Cell.t) =
    match in_grid cell ~rows ~cols with
    | true -> environments.(cell.row).(cell.col)
    | false -> Environment.Forest
  in
  let checkpoint_surface_errors =
    List.concat_map spec.checkpoints ~f:(fun (checkpoint : Checkpoint.t) ->
      let index = checkpoint.index in
      List.filter_map checkpoint.cells ~f:(fun cell ->
        let surface = surface_at cell in
        match Surface.equal surface Road with
        | true -> None
        | false ->
          Some
            (Or_error.error_s
               [%message
                 "checkpoint cell must be on road"
                   (index : int)
                   (cell : Cell.t)
                   (surface : Surface.t)])))
  in
  let start_surface_errors =
    List.filter_mapi spec.start_grid ~f:(fun slot (pose : Pose.t) ->
      let cell = Cell.of_vec2 pose.pos ~cell_size:spec.cell_size in
      let surface = surface_at cell in
      match Surface.equal surface Road with
      | true -> None
      | false ->
        Some
          (Or_error.error_s
             [%message
               "start slot must be on road"
                 (slot : int)
                 ~pos:(pose.pos : Vec2.t)
                 (cell : Cell.t)
                 (surface : Surface.t)]))
  in
  let feature_errors =
    List.concat_mapi
      spec.features
      ~f:(fun feature_index (feature : Spec.Feature_spec.t) ->
        let kind = feature.kind in
        let kind_errors =
          match kind with
          | Ice_patch ->
            [ Or_error.error_s
                [%message
                  "ice patches cannot be authored; they are spawned in play"
                    (feature_index : int)]
            ]
          | Bridge | Gate | Stalactite -> []
        in
        let surface_errors =
          List.filter_map feature.cells ~f:(fun cell ->
            let surface = surface_at cell in
            match Surface.equal surface Road with
            | true -> None
            | false ->
              Some
                (Or_error.error_s
                   [%message
                     "feature cell must be on road"
                       (feature_index : int)
                       (kind : Feature.Kind.t)
                       (cell : Cell.t)
                       (surface : Surface.t)]))
        in
        let environment_errors =
          match kind with
          | Stalactite ->
            List.filter_map feature.cells ~f:(fun cell ->
              let environment = environment_at cell in
              match Environment.equal environment Cave with
              | true -> None
              | false ->
                Some
                  (Or_error.error_s
                     [%message
                       "stalactite cells must be over cave"
                         (feature_index : int)
                         (cell : Cell.t)
                         (environment : Environment.t)]))
          | Bridge | Gate | Ice_patch -> []
        in
        kind_errors @ surface_errors @ environment_errors)
  in
  let overlap_errors =
    let (_ : Cell.Set.t), errors =
      List.foldi
        spec.features
        ~init:(Cell.Set.empty, [])
        ~f:(fun feature_index (claimed, errors) (feature : Spec.Feature_spec.t) ->
          List.fold
            feature.cells
            ~init:(claimed, errors)
            ~f:(fun (claimed, errors) cell ->
              match Set.mem claimed cell with
              | true ->
                let error =
                  Or_error.error_s
                    [%message
                      "feature footprints must not overlap"
                        (feature_index : int)
                        ~kind:(feature.kind : Feature.Kind.t)
                        (cell : Cell.t)]
                in
                claimed, error :: errors
              | false -> Set.add claimed cell, errors))
    in
    List.rev errors
  in
  let reachability_errors =
    (* Worst-case sabotage: every authored footprint blocks at once —
       every gate closed, every bridge collapsed, every stalactite
       fallen. A lap must survive even that. *)
    let blocked =
      List.fold
        spec.features
        ~init:Cell.Set.empty
        ~f:(fun blocked (feature : Spec.Feature_spec.t) ->
          List.fold feature.cells ~init:blocked ~f:Set.add)
    in
    let passable (cell : Cell.t) =
      in_grid cell ~rows ~cols
      && not (Surface.is_solid surfaces.(cell.row).(cell.col))
      && not (Set.mem blocked cell)
    in
    (* BFS over 4-connected passable cells. *)
    let reachable_from start_cells =
      let queue = Queue.create () in
      let visit visited cell =
        match passable cell && not (Set.mem visited cell) with
        | true ->
          Queue.enqueue queue cell;
          Set.add visited cell
        | false -> visited
      in
      let seeded = List.fold start_cells ~init:Cell.Set.empty ~f:visit in
      let rec loop visited =
        match Queue.dequeue queue with
        | None -> visited
        | Some (cell : Cell.t) ->
          let visited =
            List.fold
              [ { cell with col = cell.col - 1 }
              ; { cell with col = cell.col + 1 }
              ; { cell with row = cell.row - 1 }
              ; { cell with row = cell.row + 1 }
              ]
              ~init:visited
              ~f:visit
          in
          loop visited
      in
      loop seeded
    in
    let checkpoints = Array.of_list (sorted_checkpoints spec.checkpoints) in
    let checkpoint_count = Array.length checkpoints in
    let lap_errors =
      List.init checkpoint_count ~f:(fun to_index ->
        let (from : Checkpoint.t) =
          checkpoints.((to_index + checkpoint_count - 1) mod checkpoint_count)
        in
        let (target : Checkpoint.t) = checkpoints.(to_index) in
        let reachable = reachable_from from.cells in
        match List.exists target.cells ~f:(Set.mem reachable) with
        | true -> Ok ()
        | false ->
          Or_error.error_s
            [%message
              "checkpoint is unreachable from the previous checkpoint with \
               every feature blocking"
                ~from_index:(from.index : int)
                ~to_index:(target.index : int)])
    in
    let start_errors =
      let (target : Checkpoint.t) = checkpoints.(1) in
      List.filter_mapi spec.start_grid ~f:(fun slot (pose : Pose.t) ->
        let cell = Cell.of_vec2 pose.pos ~cell_size:spec.cell_size in
        let reachable = reachable_from [ cell ] in
        match List.exists target.cells ~f:(Set.mem reachable) with
        | true -> None
        | false ->
          Some
            (Or_error.error_s
               [%message
                 "checkpoint 1 is unreachable from start slot with every \
                  feature blocking"
                   (slot : int)
                   (cell : Cell.t)]))
    in
    lap_errors @ start_errors
  in
  List.concat
    [ checkpoint_surface_errors
    ; start_surface_errors
    ; feature_errors
    ; overlap_errors
    ; reachability_errors
    ]
;;

let build (spec : Spec.t) ~surfaces ~environments =
  let checkpoints = Array.of_list (sorted_checkpoints spec.checkpoints) in
  let initial_features =
    List.mapi spec.features ~f:(fun i (feature : Spec.Feature_spec.t) ->
      let payload : Feature.Payload.t =
        match feature.kind with
        | Bridge -> Bridge { phase = Intact }
        | Gate -> Gate { phase = Open }
        | Stalactite -> Stalactite { phase = Hanging }
        | Ice_patch ->
          (* Rejected by [semantic_errors]; [build] runs only on
             validated specs. *)
          raise_s
            [%message
              "BUG: authored ice patch survived validation"
                ~feature_index:(i : int)]
      in
      { Feature.id = Feature_id.of_int i; cells = feature.cells; payload })
  in
  { name = spec.name
  ; laps_to_win = spec.laps_to_win
  ; cell_size = spec.cell_size
  ; surfaces
  ; environments
  ; checkpoints
  ; start_grid = spec.start_grid
  ; initial_features
  }
;;

let load sexp =
  let open Or_error.Let_syntax in
  let%bind spec = Or_error.try_with (fun () -> Spec.t_of_sexp sexp) in
  let surfaces = grid_of_rows spec.surfaces in
  let environments = grid_of_rows spec.environments in
  let rows = Array.length surfaces in
  let cols =
    match rows with
    | 0 -> 0
    | _ -> Array.length surfaces.(0)
  in
  let%bind () = Or_error.combine_errors_unit (shape_errors spec ~rows ~cols) in
  let%bind () =
    Or_error.combine_errors_unit
      (semantic_errors spec ~surfaces ~environments ~rows ~cols)
  in
  Ok (build spec ~surfaces ~environments)
;;

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

let cell_at t v = Cell.of_vec2 v ~cell_size:t.cell_size
let checkpoints t = t.checkpoints

let checkpoint_at t cell =
  Array.find_map t.checkpoints ~f:(fun (checkpoint : Checkpoint.t) ->
    match List.mem checkpoint.cells cell ~equal:Cell.equal with
    | true -> Some checkpoint.index
    | false -> None)
;;

let start_grid t = t.start_grid
let initial_features t = t.initial_features
