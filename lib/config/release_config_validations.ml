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

let any_list name f = function
  | `List l ->
      if List.exists (fun x -> f x <> `Valid) l then
        `Invalid (sprintf "%s_list: not a %s list" name name)
      else
        `Valid
  | _ ->
      `Invalid (sprintf "%s_list: not a list" name)

let bool_list = any_list "bool" bool
let int_list = any_list "int" int
let float_list = any_list "float" float
let string_list = any_list "string" string

let int_in_range (min, max) = function
  | `Int x ->
      if x >= min && x <= max then `Valid
      else `Invalid "int_in_range: not in range"
  | _ ->
      `Invalid "int_in_range: not an int"

let string_matching re = function
  | `Str s ->
      if Str.string_match (Str.regexp re) s 0 then
        `Valid
      else
        `Invalid (sprintf "string_matching: %s doesn't match %s" s re)
  | _ ->
      `Invalid "string_matching: not a string"

let file_with f name err = function
  | `Str file ->
      (try
        let st = Unix.lstat file in
        if f st then `Valid
        else `Invalid (sprintf "%s: %s %s" name file err)
      with
      | Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "%s: %s: %s" name file (Unix.error_message e))
      | e ->
        `Invalid (sprintf "%s: %s: %s" name file (Printexc.to_string e)))
  | _ -> `Invalid (sprintf "%s: not a string" name)

let existing_file =
  file_with
    (fun st -> st.Unix.st_kind = Unix.S_REG) 
    "existing_file"
    "is not a regular file"

let file_with_mode m =
  file_with
    (fun st -> st.Unix.st_perm = m)
    "file_with_mode"
    (sprintf "must have mode 0%o" m)

let nonempty_file =
  file_with
    (fun st -> st.Unix.st_size > 0) 
    "nonempty_file"
    "is empty"

let file_with_owner u =
  file_with
    (fun st -> st.Unix.st_uid = (Unix.getpwnam u).Unix.pw_uid)
    "file_with_owner"
    (sprintf "must be owned by %s" u)

let file_with_group g =
  file_with
    (fun st -> st.Unix.st_gid = (Unix.getgrnam g).Unix.gr_gid)
    "file_with_group"
    (sprintf "must have group %s" g)

let existing_directory = function
  | `Str f ->
      (try
        let st = Unix.lstat f in
        if st.Unix.st_kind = Unix.S_DIR then `Valid
        else `Invalid (sprintf "existing_directory: %s is not a directory" f)
      with Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_file: %s: %s" f (Unix.error_message e)))
  | _ -> `Invalid "existing_directory: not a string"

let existing_dirname = function
  | `Str p ->
      (try
        ignore (Unix.lstat (Filename.dirname p));
        `Valid
      with Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_dirname: %s %s" p (Unix.error_message e)))
  | _ -> `Invalid "existing_dirname: not a string"

let existing_user = function
  | `Str u ->
      (try
        ignore (Unix.getpwnam u);
        `Valid
      with
      | Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_user: %s: %s" u (Unix.error_message e))
      | Not_found ->
        `Invalid (sprintf "existing_user: %s: user not found" u))
  | _ -> `Invalid "existing_user: not a string"

let unprivileged_user = function
  | `Str u ->
      (try
        let pw = Unix.getpwnam u in
        if pw.Unix.pw_uid <> 0 then `Valid
        else `Invalid (sprintf "user %s is privileged" u)
      with
      | Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "unprivileged_user: %s: %s" u (Unix.error_message e))
      | Not_found ->
        `Invalid (sprintf "unprivileged_user: %s: user not found" u))
  | _ -> `Invalid "unprivileged_user: not a string"

let existing_group = function
  | `Str g ->
      (try
        ignore (Unix.getgrnam g);
        `Valid
      with
      | Unix.Unix_error (e, _, _) ->
        `Invalid (sprintf "existing_group: %s: %s" g (Unix.error_message e))
      | Not_found ->
        `Invalid (sprintf "existing_group: %s: group not found" g))
  | _ -> `Invalid "existing_group: not a string"

let int_in l = function
  | `Int i ->
      if List.mem i l then
        `Valid
      else
        `Invalid (sprintf "one_of_ints: %d not found" i)
  | _ ->
      `Invalid "one_of_ints: not an int"

let string_in l = function
  | `Str s ->
      if List.mem s l then
        `Valid
      else
        `Invalid (sprintf "one_of_strings: %s not found" s)
  | _ ->
      `Invalid "one_of_strings: not a string"