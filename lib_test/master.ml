open Lwt
open Printf
open Ipc

module Option = Release_option

let slave_connections = ref None

let ipc_handler fd =
  let handler req =
    let s = SlaveIpcOps.string_of_request req in
    lwt () = Lwt_log.notice_f "got request: %s" s in
    match req with
    | SlaveIpcOps.Req1 pid -> return (SlaveIpcOps.Resp1 pid)
    | SlaveIpcOps.Req2 pid -> return (SlaveIpcOps.Resp2 pid) in
  SlaveIpc.handle_request fd handler

let control_connection_handler fd =
  let handler req =
    match req with
    | ControlIpcOps.Req s ->
        lwt () = Lwt_log.notice_f "got control request: %s" s in
        return (ControlIpcOps.response_of_string (String.uppercase s))
    | ControlIpcOps.Broadcast s ->
        let get_conns = Option.some !slave_connections in
        let slave_conns = get_conns () in
        lwt () = Lwt_list.iter_p
          (fun (_, fd) -> SlaveIpc.write_response fd (SlaveIpcOps.Broadcast s))
          slave_conns in
        return (ControlIpcOps.Broadcast_sent) in
  ControlIpc.handle_request ~timeout:5. fd handler

let lwt_ignore _ = return_unit

let store_slave_connections get_conns =
  slave_connections := Some (get_conns);
  return_unit

let () =
  let slave_exec = sprintf "%s/_build/lib_test/test_slave" (Unix.getcwd ()) in
  let helper_exec = sprintf "%s/_build/lib_test/test_helper" (Unix.getcwd ()) in
  Release.master_slaves
    ~background:false
    ~syslog:false
    ~lock_file:(sprintf "/var/run/%s.pid" (Filename.basename Sys.argv.(0)))
    ~control:("/tmp/master.socket", control_connection_handler)
    ~main:store_slave_connections
    ~slaves:[ slave_exec,  ipc_handler, 1
            ; helper_exec, lwt_ignore,  1 ]
    ()
