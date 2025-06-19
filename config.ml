open Mirage

let stack = generic_stackv4v6 default_network

let http_srv = cohttp_server @@ conduit_direct ~tls:false stack

let http_port : int runtime_arg =
  Runtime_arg.create ~pos:__POS__ "Unikernel.Args.http_port'"
let adopt_san : bool runtime_arg =
  Runtime_arg.create ~pos:__POS__ "Unikernel.Args.adopt_san'"
let cacert_lifetime : int runtime_arg =
  Runtime_arg.create ~pos:__POS__ "Unikernel.Args.cacert_lifetime'"
let cert_lifetime : int runtime_arg =
  Runtime_arg.create ~pos:__POS__ "Unikernel.Args.cert_lifetime'"

let main =
  let packages = [
    package "mirage-crypto-rng";
    package "mirage-ptime";
    package "uri";
  ] in
  let runtime_args = [
    Runtime_arg.v http_port;
    Runtime_arg.v adopt_san;
    Runtime_arg.v cacert_lifetime;
    Runtime_arg.v cert_lifetime;
  ] in
  main ~packages ~runtime_args "Unikernel.Make" (http @-> job)

let () =
  register "ephca" [main $ http_srv]
