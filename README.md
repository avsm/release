# Release

## Introduction

Release is a multi-process Lwt-enabled daemon framework for OCaml, providing
facilities for type-safe inter-process communication and privilege-dropping.

Its goal is to make it easy to write servers that are released from the calling
terminal and to release root privileges when those are not necessary.

In this documentation, any mention of a "thread" refers to an `Lwt.t`.

All quotes are from the Pearl Jam song _Release - Master/Slave_ :)

## Build and installation

After cloning the repository, run the commands below to build Release.

    $ ocaml setup.ml -configure
    $ ocaml setup.ml -build

Documentation can be generated with the command below.

    $ ocaml setup.ml -doc

To install Release, run

    # ocaml setup.ml -install

## Forking daemons

> Oh dear dad
> Can you see me now
> I am myself
> Like you somehow

The simplest way to use the library is to simply daemonize a process. Release
provides an Lwt-enabled function to do this in the `Release` module.

    val daemon : (unit -> unit Lwt.t) -> unit Lwt.t

Upon calling `Release.daemon f`, the usual steps to create a daemon
process will be executed.

1.  The `umask` will be set to 0;
2.  `fork` will be called;
3.  The parent process exits;
4.  The child process calls `setsid`, ignores the `SIGHUP` and `SIGPIPE`
    signals, calls `fork` again and exits.
5.  The grandchild process changes the working directory to `/`, redirects
    `stdin`, `stdout` and `stderr` to `/dev/null` and finally calls `f`.

## Master/slave processes

A common pattern when writing multi-process servers is to have a master process
and _n_ slave processes. Usually the master process runs as a privileged user,
while the slaves run unprivileged. This allows one to design a server such
that the bulk of the code runs as a normal user in a slave process, and a
minimum amount of code that actually requires root privileges is implemented
in the master process. Thus, in case of a bug, the likelihood that it can be
exploited with root escalation is considerably decreased.

Consider the type of an inter-process communication callback function, defined
as `Release_ipc.handler`:

    type handler = (Lwt_unix.file_descr -> unit Lwt.t)

The simple case of a master process and one slave process is implemented in
the function `Release.master_slave`.

    val master_slave :
         slave:(Lwt_io.file_name * Release_ipc.handler)
      -> ?background:bool
      -> ?syslog:bool
      -> ?privileged:bool
      -> ?control:(Lwt_io.file_name * Release_ipc.handler)
      -> ?main:((unit -> (int * Lwt_unix.file_descr) list) -> unit Lwt.t)
      -> lock_file:Lwt_io.file_name
      -> unit -> unit

The `slave` argument is a tuple whose first argument is the path to the slave
process executable. The second argument is a callback function that is used by
the master to handle inter-process communication with the slave. This function
receives the file descriptor to be used as a communication channel with the
slave process. More details about slave processes and IPC in Release will be
described in more details below.

The `background` argument indicates whether `Release.daemon` will be called.
The `syslog` argument indicates if the syslog facilities from the `Lwt_log`
module will be enabled. If the master process is supposed to run as root, then
the `privileged` argument must be set to `true`.

The `master_slave` function will create a lock file in the path given in the
`lock_file` argument. This file will contain the PID of the master process.
If the lock file already exists and contains the PID of a running process,
the master process will refuse to start.

The `control` argument consists of a tuple specifying the path to a Unix socket
and a callback function. The master process will create and listen on this
socket on startup. This is useful for the implementation of control programs
that communicate with the master process.

If given, the `main` callback function argument will be called with a function
that returns a list of PID and file descriptors pairs corresponding to the
currently running slave processes and the IPC sockets that can be used by the
master process for communication.
This list can be useful to implement broadcast-style messaging from the master
to the slaves.

The general case of _n_ slave processes is handled by the function
`Release.master_slaves`.

    val master_slaves :
         ?background:bool
      -> ?syslog:bool
      -> ?privileged:bool
      -> ?control:(Lwt_io.file_name * Release_ipc.handler)
      -> ?main:((unit -> (int * Lwt_unix.file_descr) list) -> unit Lwt.t)
      -> lock_file:Lwt_io.file_name
      -> slaves:(Lwt_io.file_name * Release_ipc.handler * int) list
      -> unit -> unit

This function generalizes `Release.master_slave`, allowing the creation of
heterogeneous groups of slave process via the `slaves` argument. This argument
is a list of 3-element tuples containing the path to the slave executables,
the IPC callback function and the number of processes that will be created for
the given executable.

### Slaves

> I'll ride the wave
> Where it takes me
> I'll hold the pain
> Release me

When a slave process is run, some code must be run in order to setup
communication with the master, and also to drop privileges to a non-root user.
The `Release.me` function deals with this:

    val me : ?syslog:bool
          -> ?user:string
          -> main:(Lwt_unix.file_descr -> unit Lwt.t)
          -> unit -> unit

The `syslog` argument works like in `master_slave`. The `user` argument, if
given, indicates the user whose UID and GID the slave process will set its own
IDs to. This argument can only be given is `privileged` is `true` in the master
process.

The `main` argument is a function that returns the slave's main thread. It
accepts a file descriptor for communication with the master process.

### Inter-process communication

> I'll wait up in the dark
> For you to speak to me

Inter-process communication in `Release` is handled in a type-safe manner in
the module `Release_ipc`.

The `Release_ipc.Make` functor receives as an argument a module with the
following signature.

    module type Ops = sig
      type request
      type response

      val string_of_request : request -> string
      val request_of_string : string -> request

      val string_of_response : response -> string
      val response_of_string : string -> response
    end

The types `request` and `response` correspond to the respective IPC operations,
and the convertion functions of requests and responses to and from strings
must be provided.

The output of `Release_ipc.Make` is a module with the signature below.

    module type S = sig
      type request
      type response

      val read : ?timeout:float
              -> Lwt_unix.file_descr
              -> [`Data of Release_buffer.t | `EOF | `Timeout] Lwt.t

      val write : Lwt_unix.file_descr -> Release_buffer.t -> unit Lwt.t

      val read_request : ?timeout:float
                      -> Lwt_unix.file_descr
                      -> [`Request of request | `EOF | `Timeout] Lwt.t

      val read_response : ?timeout:float
                       -> Lwt_unix.file_descr
                       -> [`Response of response | `EOF | `Timeout] Lwt.t

      val write_request : Lwt_unix.file_descr -> request -> unit Lwt.t

      val write_response : Lwt_unix.file_descr -> response -> unit Lwt.t

      val make_request : ?timeout:float
                      -> Lwt_unix.file_descr
                      -> request
                      -> ([`Response of response | `EOF | `Timeout] -> 'a Lwt.t)
                      -> 'a Lwt.t

      val handle_request : ?timeout:float
                        -> ?eof_warning:bool
                        -> Lwt_unix.file_descr
                        -> (request -> response Lwt.t)
                        -> unit Lwt.t
    end

The functions `read` and `write` will perform these operations on the IPC file
descriptor given as an argument, and operate on buffers.

The `read_{request,response}` and `write_{request,response}` work similarly,
but are higher-level, and operate on the `request` and `response` types,
doing the buffer conversion implicitly.

The functions `make_request` and `handle_request` are IPC helpers wrapping
`read` and `write`. A slave process can call `make_request fd req handler` to
make an IPC request to the master process and wait for a response, which will
be passed as an argument to the `handler` callback. The master process can call
`handle_request fd handler` to wait for an IPC request from a slave. This
request will be passed to the callback function, which must return a response
that will be written back to the slave.

#### Control sockets

It may be useful for slaves to have control sockets like the one available
to the master process. This can be useful for writing control programs or for
communication between slave processes. The `Release_ipc` module provides the
`control_socket` function to help setting up the socket and spawning a handler
thread.

    val control_socket : Lwt_io.file_name -> Release_ipc.handler -> unit Lwt.t

#### The IPC protocol

Release uses a very simple IPC protocol. This information is not necessary for
writing applications using this library, but it is useful for creating control
programs or scripts in languages other than OCaml, which can't use Release
(see the `control` argument described above).

Every Release IPC message consists of a 4-byte field containing the length of
the payload portion of the message and a payload field of variable length.
Thus, a message containing the payload string "hello" will have the length field
set to `5` (the length of the string) and the payload field will be the string
itself.

Higher-level protocols are left for the library users to implement according
to the needs of their respective applications.

## Extras

### The `Release_buffer` module

`Release_buffer` is provided in a separate, `release.buffer`, but it is loaded
by default when `Release` is used.

This module provides a buffer whose implementation is based on OCaml's
`Bigarray` type to minimize data copying. It is used by Release in its I/O
functions.

Please check the `ocamldoc` documentation for the module interface.

### The `Release_io` module

This module exports utility I/O functions that are useful when dealing with
network I/O.

The functions in this module are based on the `Release_buffer.t` type, which
has already appeared in some function signatures in the IPC module. This
buffer is a wrapper around the `Lwt_bytes.t` type, which in turn uses OCaml's
`Bigarray` module to minimize data-copying. See the `Release_buffer` module
documentation for the list of available buffer-related functions.

The first function in the module is `Release_io.read_once`. It has similar
semantics to the usual `Unix.read`, but works on `Release_buffer.t`.

    val read_once : Lwt_unix.file_descr
                 -> Release_buffer.t
                 -> int
                 -> int
                 -> int Lwt.t

Calling `Release_io.read_once fd buf off n` will read at most `n` bytes
from `fd` and store them into `buf` starting at offset `off`. This function
is safe against temporary errors, retrying on `Unix.EINTR` and `Unix.EAGAIN`
automatically.

The second function is `Release_io.read`, which has the following signature.

    val read : ?timeout:float
            -> Lwt_unix.file_descr
            -> int
            -> [`Data of Release_buffer.t | `EOF | `Timeout] Lwt.t

Calling `Release_io.read fd n` will try to read at most `n` bytes from `fd`,
returning the appropriate result. Like `Release_io.read_once`, this function
is safe against temporary errors.

The third function is `Release_io.write`.

    val write : Lwt_unix.file_descr -> Release_buffer.t -> unit Lwt.t

Calling `Release_io.write fd buf` will ensure that the full length of buffer
`buff` is written on file descriptor `fd`. This function is also safe against
`Unix.EINTR` and `Unix.EAGAIN`.

### The `Release_socket` module

This module contains utility socket functions. Currently the only exported
function is `Release_socket.accept_loop`.

    val accept_loop : ?backlog:int
                   -> ?timeout:float
                   -> Lwt_unix.socket_type
                   -> Lwt_unix.sockaddr
                   -> (Lwt_unix.file_descr -> unit Lwt.t)
                   -> unit Lwt.t

This function implements a traditional accept loop, spawning one thread per
client connection. The function creates a socket of the specified type, binds
it to the given address and listens for client connections. When a new
connection is accepted, the callback function given as the last argument is
executed in a separate thread (which may be interrupted depending on the
`timeout` argument), while `accept_loop` goes back to wait for new connections.

## Release sub-packages

### The `Release_bytes` module

When writing network-based daemons, the need to implement some kind of binary
protocol is very common. Very often, these protocols have numeric fields that
must be read or written by the application. Since the network I/O functions
take buffers as arguments, the need to perform integer reads writes from and
into buffers, respectively, is quite frequent.

The Release library offers the `Release_bytes` module to help in such
conversions. This module contains a set of functions that take a buffer as an
argument and read or write integers of various sizes at a given offset on the
buffer. The functions that read and write single bytes are available directly
`Release_bytes`, while functions for integers of other sizes can be accessed
from the modules `Release_bytes.Big_endian` and `Release_bytes.Little_endian`.

The functions available in `Release_bytes`, with their respective
signatures, are listed below.

* `val read_byte_at : int -> Release_buffer.t -> int`
* `val read_byte : Release_buffer.t -> int`
* `val write_byte : int -> Buffer.t -> unit`

The following functions are available in both `Release_bytes.Little_endian` and
`Release_bytes.Little_endian`.

* `val read_int16_at : int -> Release_buffer.t -> int`
* `val read_int16 : Release_buffer.t -> int`
* `val write_int16_byte : int -> Buffer.t -> unit`
* `val write_int16 : int -> Buffer.t -> unit`

* `val read_int_at : int -> Release_buffer.t -> int`
* `val read_int : Release_buffer.t -> int`
* `val write_int_byte : int -> Buffer.t -> unit`
* `val write_int : int -> Buffer.t -> unit`

* `val read_int32_at : int -> Release_buffer.t -> int32`
* `val read_int32 : Release_buffer.t -> int32`
* `val write_int32_byte : int32 -> Buffer.t -> unit`
* `val write_int32 : int32 -> Buffer.t -> unit`

* `val read_uint32_at : int -> Release_buffer.t -> Uint32.t`
* `val read_uint32 : Release_buffer.t -> Uint32.t`
* `val write_uint32_byte : Uint32.t -> Buffer.t -> unit`
* `val write_uint32 : Uint32.t -> Buffer.t -> unit`

* `val read_int64_at : int -> Release_buffer.t -> int64`
* `val read_int64 : Release_buffer.t -> int64`
* `val write_int64_byte : int64 -> Buffer.t -> unit`
* `val write_int64 : int64 -> Buffer.t -> unit`

* `val read_uint64_at : int -> Release_buffer.t -> Uint64.t`
* `val read_uint64 : Release_buffer.t -> Uint64.t`
* `val write_uint64_byte : Uint64.t -> Buffer.t -> unit`
* `val write_uint64 : Uint64.t -> Buffer.t -> unit`

* `val read_uint128_at : int -> Release_buffer.t -> Uint128.t`
* `val read_uint128 : Release_buffer.t -> Uint128.t`
* `val write_uint128_byte : Uint128.t -> Buffer.t -> unit`
* `val write_uint128 : Uint128.t -> Buffer.t -> unit`

### The `Release_config` module

This module provides an interface to help dealing with configuration files in
Release applications. A Release configuration file uses a simple `key = value`
format with support for sections, similar to `.ini` configuration files.

`Release_config` values can be integers, floats, strings, booleans, regular
expressions, log levels or lists containing one of those types. Configuration
files are validated against a specification provided by the application, which
states the default value, if any, and a list of validations for each
configuration directive.

The `Release_config_values` module provides some helpers for setting default
values in configuration specifications:

* `default_bool`
* `default_int`
* `default_float`
* `default_string`
* `default_regexp`
* `default_log_level`
* `default_bool_list`
* `default_int_list`
* `default_float_list`
* `default_string_list`

The `Release_config_validations` provides helpers for specifying validation
lists in a configuration:

* `bool`: the value is a boolean
* `int`: the value is an integer
* `float`: the value is a float
* `string`: the value is a string
* `regexp`: the value is a regular expression
* `log_level`: the value is a log level
* `bool_list`: the value is a list of booleans
* `int_list`: the value is a list of integers
* `float_list`: the value is a list of floats
* `string_list`: the value is a list of strings
* `int_in_range`: the value is an integer in the given inclusive range
* `int_greater_than`: the value is greater than the given integer
* `int_less_than`: the value is less than the given integer
* `float_in_range`: the value is a float in the given range
* `float_greater_than`: the value is greater than the given float
* `float_less_than`: the value is less than the given float
* `string_matching`: the value matches a regexp built from the given string
* `int_in`: the value is one of the integers in the given list
* `string_in`: the value is one of the strings in the given list
* `existing_file`: the value is an existing file
* `nonempty_file`: the value is a non-empty file
* `file_with_mode`: the value is a file with the given mode
* `file_with_owner`: the value is a file with the given owner
* `file_with_group`: the value is a file with the given group
* `existing_directory`: the value is an existing directory
* `existing_dirname`: the values's directory name of exists
* `block_device`: the value is a block device
* `character_device`: the value is a character device
* `symbolic_link`: the value is a symbolic link
* `named_pipe`: the value is a named pipe
* `unix_socket`: the value is a socket
* `existing_user`: the value is an existing user
* `unprivileged_user`: the value is a non-root user
* `existing_group`: the value is an existing group
* `list_of`: the value is a list of values passing the given validation

Please refer to the `ocamldoc` documentation for the types of the above helpers.

Configuration specifications are values of type `Release_config.spec`,
constructed as below.

    type value =
      [ `Int of int
      | `Float of float
      | `Bool of bool
      | `Str of string
      | `Regexp of Str.regexp
      | `Log_level of Lwt_log.level
      | `List of (value list)
      ]

    type validation = value -> [`Valid | `Invalid of string]

    type key = string * value option * validation list

    type section =
      [ `Global of key list
      | `Section of (string * key list)
      ]

    type spec = section list

Below is an example of a configuration specification and its respective
configuration file.

    open Release_config_values
    open Release_config_validations

    let spec =
      [ `Global (* Settings which don't belong to any section *)
          [ "user", None (* required parameter *), [unprivileged_user]
          ; "privileged", default_bool true, [bool]
          ; "read_timeout", default_int 5, int_in_range (0, 10)
          ; "log_level", default_log_level notice, [log_level]
          ]
      ; `Section ("some-section",
          [ "match_with", default_regexp /^[a-z]+$/, [regexp]
          ; "tmp", default_string "/tmp", one_of_strings ["/tmp"; "/var/tmp"]
          ])
      ; `Section ("another-section",
          [ "privileged_users", default_string_list ["root"], [list_of existing_user]
          ])
      ]

With the specification above, every parameter can be ommited, with the exception
of the first global directive, which has no default value and therefore must
be present in the file.

Below is a possible configuration file that matches the above specification.

    # Global settings
    user         = "foo"  # string
    privileged   = false  # boolean
    read_timeout = 1      # integer
    log_level    = debug  # log_level

    [some-section]  # section declaration
    match_with  = /^.+$/  # regular expression
    tmp         = "/tmp"  # string

    [another-section]  # another section declaration
    privileged_users = ["root", "admin"]  # list of strings
