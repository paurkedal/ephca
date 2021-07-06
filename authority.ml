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

open Prereq

module DN = struct
  open X509.Distinguished_name
  open Relative_distinguished_name
  let pp = pp
  let cn x = singleton (CN x)
  let ou x = singleton (OU x)
  let serialnumber x = singleton (Serialnumber x)
end
module CSR = X509.Signing_request
let directory_name dn = X509.General_name.(singleton Directory [dn])

let prefix = DN.[cn "EphCA"]
let cacert_dn = prefix @ DN.[cn "Ephemeral CA for Testing"]
let cacert_bits = 4096
let cacert_lifetime = Ptime.Span.v (1, 0L)
let cacert_serial_number = Z.zero
let cert_prefix_for_origin = DN.(prefix @ [ou "Apparent Origin"])
let cert_prefix_for_serial_number = DN.(prefix @ [ou "Anonymous"])
let cert_lifetime = Ptime.Span.v (1, 0L)

let log_src = Logs.Src.create "authority"
module Log = (val Logs.src_log log_src)

let pp_ptime = Ptime.pp_rfc3339 ()

module Make (Pclock : Mirage_clock.PCLOCK) = struct

  type t = {
    own_key: X509.Private_key.t;
    own_cert: X509.Certificate.t;
    mutable last_serial_number: Z.t;
  }

  let create () =
    let valid_from = Pclock.now_d_ps () |> Ptime.v in
    let/? valid_until =
      Ptime.add_span valid_from cacert_lifetime
        |> Option.to_result ~none:(`Msg "End time out of range.")
    in
    Log.info (fun f ->
      f "Creating CA <%a> valid from %a to %a."
        DN.pp cacert_dn pp_ptime valid_from pp_ptime valid_until);
    let own_key = `RSA (Mirage_crypto_pk.Rsa.generate ~bits:cacert_bits ()) in
    let/? ca_csr = CSR.create cacert_dn own_key in
    let extensions =
      let open X509.Extension in
      let key_id = X509.Public_key.id CSR.((info ca_csr).public_key) in
      let authority_key_id =
        (Some key_id, directory_name cacert_dn, Some cacert_serial_number)
      in
      empty
        |> add Basic_constraints (true, (true, None))
        |> add Key_usage (true, [`Digital_signature; `Key_cert_sign; `CRL_sign])
        |> add Subject_key_id (false, key_id)
        |> add Authority_key_id (false, authority_key_id)
    in
    let/? own_cert =
      CSR.sign ~valid_from ~valid_until ~extensions ~serial:cacert_serial_number
        ca_csr own_key cacert_dn
    in
    Log.debug (fun f -> f "Created CA cert: %a" X509.Certificate.pp own_cert);
    Ok {own_key; own_cert; last_serial_number = cacert_serial_number}

  let own_dn ca = X509.Certificate.subject ca.own_cert
  let own_cert ca = ca.own_cert

  let sign ~csr ?(subject_spec = `Serial) ca =
    let valid_from = Pclock.now_d_ps () |> Ptime.v in
    let/? valid_until =
      Ptime.add_span valid_from cert_lifetime
        |> Option.to_result ~none:(`Msg "End time out of range.")
    in
    ca.last_serial_number <- Z.(ca.last_serial_number + one);
    let serial = ca.last_serial_number in
    let subject =
      (match subject_spec with
       | `Origin origin ->
          DN.(cert_prefix_for_origin @ [cn origin])
       | `Serial ->
          let suffix = DN.[serialnumber (Z.to_string serial)] in
          cert_prefix_for_serial_number @ suffix)
    in
    let extensions =
      let open X509.Extension in
      let key_id = X509.Public_key.id CSR.((info csr).public_key) in
      let authority_key_id =
        let id = X509.Public_key.id (X509.Certificate.public_key ca.own_cert) in
        (Some id, directory_name cacert_dn, Some cacert_serial_number)
      in
      empty
        |> add Basic_constraints (false, (false, None))
        |> add Key_usage (false,
                [`Digital_signature; `Content_commitment; `Key_encipherment])
        |> add Subject_key_id (false, key_id)
        |> add Authority_key_id (false, authority_key_id)
    in
    Log.info (fun f ->
      f "Signing <%a>, valid %a/%a."
        DN.pp subject pp_ptime valid_from pp_ptime valid_until);
    CSR.sign ~valid_from ~valid_until ~extensions ~subject ~serial
      csr ca.own_key (own_dn ca)

end
