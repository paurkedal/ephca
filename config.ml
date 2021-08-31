open Mirage

let stack = generic_stackv4v6 default_network

let http_srv = cohttp_server @@ conduit_direct ~tls:false stack

let http_port =
  let doc = Key.Arg.info ~doc:"Listening HTTP port." ["http-port"] in
  Key.(create "http_port" Arg.(opt int 80 doc))

let adopt_san =
  let doc =
    Key.Arg.info ~doc:"Adopt unvalidated SAN extensions from CSRs."
      ["adopt-san"]
  in
  Key.(create "adopt_san" Arg.(opt bool false doc))

let main =
  let packages = [
    package "mirage-crypto-rng" ~sublibs:["lwt"];
    package "uri";
  ] in
  let keys = [Key.abstract http_port; Key.abstract adopt_san] in
  foreign ~packages ~keys "Unikernel.Make"
  (pclock @-> http @-> job)

let () =
  register "ephca" [main $ default_posix_clock $ http_srv]
