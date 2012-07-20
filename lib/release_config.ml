open Printf
open Release_config_types

type validation = value -> [`Valid | `Invalid of string]

type key =
  [ `Required of (string * validation option)
  | `Optional of (string * validation option)
  ]

type section =
  [ `Required of (string * key list)
  | `Optional of (string * key list)
  | `Global of key list
  ]

module type Ops = sig
  val spec : section list
end 

module type S = sig
  type t

  val parse : Lwt_io.file_name -> [`Configuration of t | `Error of string]
  val get : t -> ?section:string -> string -> unit -> value option
  val reset : unit -> unit
end

module Make(O : Ops) : S = struct
  type t = (string, (string, value) Hashtbl.t) Hashtbl.t

  let hash_find h k =
    try Some (Hashtbl.find h k)
    with Not_found -> None

  let validate_and cont validation value =
    match Option.apply `Valid value validation with
    | `Valid -> cont ()
    | `Invalid r -> `Invalid r

  let rec validate_keys keys settings =
    match keys with
    | [] ->
        `Valid
    | key::rest ->
        let keep_validating () =
          validate_keys rest settings in
        let missing_required_key k () =
          `Invalid (sprintf "directive '%s' unspecified" k) in
        let name, validation, deal_with_missing =
          match key with
          | `Required (k, v) -> k, v, missing_required_key k
          | `Optional (k, v) -> k, v, keep_validating in
        Option.either
          deal_with_missing
          (validate_and keep_validating validation)
          (hash_find settings name)

  let validate_keys_and cont keys settings =
    match validate_keys keys settings with
    | `Valid -> cont ()
    | `Invalid r -> `Invalid r

  let rec validate_sections sections conf =
    match sections with
    | [] ->
      `Valid
    | section::sections ->
        let keep_validating () =
          validate_sections sections conf in
        let missing_required_section s () =
          `Invalid (sprintf "section '%s' missing" s) in
        let name, keys, deal_with_missing =
          match section with
          | `Global ks -> Config.global_section, ks, keep_validating
          | `Required (s, ks) -> s, ks, missing_required_section s
          | `Optional (s, ks) -> s, ks, keep_validating in
        Option.either
          deal_with_missing
          (validate_keys_and keep_validating keys)
          (hash_find conf name)

  let validate =
    validate_sections O.spec

  let join_with sep l =
    List.fold_left (fun joined i -> joined ^ sep ^ (string_of_int i)) "" l

  exception Error of string

  let join_errors errors =
    let concat msg (err, line) = msg ^ (sprintf "%s in line %d\n" err line) in
    List.fold_left concat "" errors

  let parse file =
    let ch = open_in file in
    try
      let lexbuf = Lexing.from_channel ch in
      while true do
        Config_parser.input Config_lexer.token lexbuf
      done;
      assert false (* not reached *)
    with End_of_file ->
      close_in ch;
      match Config.errors () with
      | [] ->
          (try
            let conf = Config.configuration in
            match validate conf with
            | `Valid -> `Configuration conf
            | `Invalid reason -> `Error reason
          with Error reason ->
            `Error reason)
      | errors ->
          `Error (join_errors errors)

  let get conf ?(section = Config.global_section) key () =
    match hash_find conf section with
    | Some settings -> hash_find settings key
    | None -> None

  let reset = Config.reset
end