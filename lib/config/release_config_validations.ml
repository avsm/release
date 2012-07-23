open Printf

let bool = function
  | `Bool _ -> `Valid
  | _ -> `Invalid "bool: not a bool"

let int = function
  | `Int _ -> `Valid
  | _ -> `Invalid "int: not an int"

let float = function
  | `Float _ -> `Valid
  | _ -> `Invalid "float: not a float"

let string = function
  | `Str _ -> `Valid
  | _ -> `Invalid "string: not a string"

let int_in_range (min, max) = function
  | `Int x ->
      if x >= min && x <= max then `Valid
      else `Invalid "int_in_range: not in range"
  | _ ->
      `Invalid "int_in_range: not an int"

let string_matching re = function
  | `Str s ->
      if Str.string_match (Str.regexp re) s 0 then `Valid
      else `Invalid "string_matching: no match"
  | _ ->
      `Invalid "string_matching: not a string"

let existing_file = function
  | `Str f ->
      (try
        let st = Unix.lstat f in
        if st.Unix.st_kind = Unix.S_REG then `Valid
        else `Invalid "existing_file: not a regular file"
      with Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_file: %s" (Unix.error_message e)))
  | _ -> `Invalid "existing_file: not a string"

let existing_basename = function
  | `Str p ->
      (try
        ignore (Unix.lstat (Filename.basename p));
        `Valid
      with Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_basename: %s" (Unix.error_message e)))
  | _ -> `Invalid "existing_basename: not a string"

let existing_user = function
  | `Str u ->
      (try
        ignore (Unix.getpwnam u);
        `Valid
      with Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_user: %s" (Unix.error_message e)))
  | _ -> `Invalid "existing_user: not a string"

let one_of_ints l = function
  | `Int i ->
      if List.mem i l then `Valid else `Invalid "one_of_ints: not found"
  | _ ->
      `Invalid "one_of_ints: not an int"

let one_of_strings l = function
  | `Str s ->
      if List.mem s l then `Valid else `Invalid "one_of_strings: not found"
  | _ ->
      `Invalid "one_of_strings: not a string"
