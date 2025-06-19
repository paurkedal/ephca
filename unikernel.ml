(* Copyright (C) 2021  Petter A. Urkedal <paurkedal@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)

open Lwt.Syntax
open Prereq

module type HTTP = Cohttp_mirage.Server.S

let log_src = Logs.Src.create "http" ~doc:"HTTP server"
module Log = (val Logs.src_log log_src)

module Args = struct
  open Cmdliner

  let http_port' =
    Arg.(value @@ opt int 80 @@ info ~doc:"Listening HTTP port." ["http-port"])

  let adopt_san' =
    let doc = "Adopt unvalidated SAN extensions from CSRs." in
    Arg.(value @@ opt bool false @@ info ~doc ["adopt-san"])

  let cacert_lifetime' =
    let doc = "Lifetime of CA certificate in seconds." in
    Arg.(value @@ opt int 86400 @@ info ~doc ["cacert-lifetime"])

  let cert_lifetime' =
    let doc = "Lifetime of issued certificates in seconds." in
    Arg.(value @@ opt int 86400 @@ info ~doc ["cert-lifetime"])

  let http_port = Mirage_runtime.register_arg http_port'
  let adopt_san = Mirage_runtime.register_arg adopt_san'
  let cacert_lifetime = Mirage_runtime.register_arg cacert_lifetime'
  let cert_lifetime = Mirage_runtime.register_arg cert_lifetime'
end

let bad_request fmt = Fmt.kstr (fun s -> Error (`Bad_request s)) fmt

let map_decode_error = Result.map_error @@ function
 | `Msg msg -> `Bad_request msg

let map_signature_error = Result.map_error @@ fun err ->
  Fmt.kstr (fun s -> `Bad_request s) "%a"
    X509.Validation.pp_signature_error err

module App (S : HTTP) = struct

  type t = {ca: Authority.t}

  let create () =
    let/? ca =
      Authority.create ()
        ~cacert_lifetime:(Ptime.Span.of_int_s (Args.cacert_lifetime ()))
        ~cert_lifetime:(Ptime.Span.of_int_s (Args.cert_lifetime ()))
        ~adopt_san:(Args.adopt_san ())
    in
    Ok {ca}

  let respond_with_error = function
   | `Bad_request msg ->
      Log.err (fun f -> f "Bad request: %s" msg);
      let headers = Cohttp.Header.of_list ["Content-Type", "text/plain"] in
      let body = Fmt.str "Bad request: %s\n" msg in
      S.respond_string ~status:`Bad_request ~headers ~body ()

  let respond_with_string_result = function
   | Ok (content_type, body) ->
      let headers = Cohttp.Header.of_list ["Content-Type", content_type] in
      S.respond_string ~status:`OK ~headers ~body ()
   | Error (`Bad_request msg) ->
      Log.err (fun f -> f "Bad request: %s" msg);
      let headers = Cohttp.Header.of_list ["Content-Type", "text/plain"] in
      let body = Fmt.str "Bad request: %s\n" msg in
      S.respond_string ~status:`Bad_request ~headers ~body ()

  let handle_info () =
    let headers = Cohttp.Header.of_list [
      "Content-Type", "text/plain";
    ] in
    let body = "Running ephca.\n" in
    S.respond_string ~status:`OK ~headers ~body ()

  let respond_with_cert format cert =
    let content_type, encode = match format with (* cf [1] *)
     | `Pem -> ("application/x-pem-file", X509.Certificate.encode_pem)
     | `Der -> ("application/pkix-cert", X509.Certificate.encode_der)
     | `Der_ca -> ("application/x-x509-ca-cert", X509.Certificate.encode_der)
    in
    let headers = Cohttp.Header.of_list ["Content-Type", content_type] in
    let body = encode cert in
    S.respond_string ~status:`OK ~headers ~body ()

  let handle_ca_cert format {ca} =
    respond_with_cert format (Authority.own_cert ca)

  let handle_crl () = assert false

  let handle_sign app request body =
    let* body = Cohttp_lwt.Body.to_string body in
    let headers = Cohttp.Request.headers request in
    let resp =
      let/? format, decoder =
        (match Cohttp.Header.get headers "Content-Type" with
         | Some ("text/plain" | "application/x-pem-file") ->
            Ok (`Pem, X509.Signing_request.decode_pem)
         | Some "application/pkcs10" ->
            Ok (`Der, X509.Signing_request.decode_der ?allowed_hashes:None)
         | None -> bad_request "Missing content type."
         | Some s -> bad_request "Cannot handle CSR of type %s." s)
      in
      let/? csr = decoder body |> map_decode_error in
      let/? cert = Authority.sign ~csr app.ca |> map_signature_error in
      Ok (format, cert)
    in
    (match resp with
     | Ok (format, cert) -> respond_with_cert format cert
     | Error err -> respond_with_error err)

  let dispatcher app request body =
    let meth = Cohttp.Request.meth request in
    let uri = Cohttp.Request.uri request in
    (match meth, List.tl (String.split_on_char '/' (Uri.path uri)) with
     | `GET, ([] | [""]) -> handle_info ()
     | `GET, ["ephca.pem"] -> handle_ca_cert `Pem app
     | `GET, ["ephca.der"] -> handle_ca_cert `Der_ca app
     | `GET, ["ephca.crl"] -> handle_crl ()
     | `POST, ["sign"] -> handle_sign app request body
     | _ -> S.respond_not_found ())

  let serve dispatch =
    let callback (_flow, cid) request body =
      let uri = Cohttp.Request.uri request in
      let cid = Cohttp.Connection.to_string cid [@alert "-deprecated"] in
      Log.info (fun f -> f "[%s] serving %s." cid (Uri.to_string uri));
      Lwt.catch (fun () -> dispatch request body)
        (fun exn ->
          Log.err (fun f -> f "Unhandled exception: %s"
            (Printexc.to_string exn));
          S.respond_error
            ~headers:(Cohttp.Header.of_list ["Content-Type", "text/plain"])
            ~status:`Internal_server_error
            ~body:"Internal Server Error\n" ())
    in
    let conn_closed (_, cid) =
      let cid = Cohttp.Connection.to_string cid [@alert "-deprecated"] in
      Log.info (fun f -> f "[%s] closing" cid)
    in
    S.make ~conn_closed ~callback ()
end

module Make (Http : HTTP) = struct

  module Http_app = App (Http)

  let start http _http_port _adapt_san _cacert_lifetime _cert_lifetime =
    (match Http_app.create () with
     | Ok app ->
        let http_port = Args.http_port () in
        let tcp = `TCP http_port in
        Log.info (fun f -> f "listening on %d/TCP" http_port);
        http tcp @@ Http_app.serve (Http_app.dispatcher app)
     | Error (#X509.Validation.signature_error as err) ->
        Log.err (fun f ->
          f "failed to start up: %a" X509.Validation.pp_signature_error err);
        Lwt.return_unit)

end

(* [1]: https://pki-tutorial.readthedocs.io/en/latest/mime.html *)
