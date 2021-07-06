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

module Make :
  functor (_ : Mirage_clock.PCLOCK) ->
sig
  type t

  val create : unit -> (t, X509.Validation.signature_error) result

  val own_cert : t -> X509.Certificate.t

  val sign :
    csr: X509.Signing_request.t ->
    ?subject_spec: [`Serial | `Origin of string] ->
    t -> (X509.Certificate.t, X509.Validation.signature_error) result

end
