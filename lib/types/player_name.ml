open! Core

type t = string [@@deriving compare, equal, sexp_of]

let max_length = 16

let is_allowed_char c =
  Char.is_alphanum c || Char.equal c '_' || Char.equal c '-'
;;

let of_string name =
  let problems =
    List.filter_map
      [ String.is_empty name, Error.of_string "player name may not be empty"
      ; ( String.length name > max_length
        , Error.create_s
            [%message
              "player name is too long" (name : string) (max_length : int)] )
      ; ( String.exists name ~f:(fun c -> not (is_allowed_char c))
        , Error.create_s
            [%message
              "player name may only contain letters, digits, '_' and '-'"
                (name : string)] )
      ]
      ~f:(fun (is_broken, problem) -> Option.some_if is_broken problem)
  in
  match problems with
  | [] -> Ok name
  | _ :: _ -> Error (Error.of_list problems)
;;

let to_string t = t
