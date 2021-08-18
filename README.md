## Synopsis

EphCA is a simple online certificate authority intended for CI or other
non-production use cases.  It creates its own CA certificate on startup and
signs certificates on request.  No authentication or validation takes place
before signing.  The certificates have serially numbered subject DNs.  The
CA key and certificate are destroyed when the application stops.

EphCA is available as a Docker container.  It is designed as a MirageOS
unikernel and can therefore also be compiled to run directly under a
hypervisor.

## Protocol

Interaction with the CA happen through the following HTTP calls:

  - `GET /ephca.pem` returns the CA certificate in PEM format.
  - `GET /ephca.der` returns the CA certificate in DER format.
  - `POST /sign` with data containing a certificate signing request returns
    a signed certificate in the same format. The format must be indicated by
    setting the `Content-Type` header to `application/x-pem-file` for PEM or
    `application/pkcs10` for DER.

## Demonstration

Start up EphCA on localhost port 8080:

    docker run --rm -it -p 8080:80 paurkedal/ephca:latest

Inspect the CA with:

    curl http://localhost:8080/ephca.pem | openssl x509 -noout -text

Create a CSR, post it to the signing service, and inspect the result:

    openssl genrsa -out testkey.pem 4096
    openssl req -new -batch -key testkey.pem -out testreq.pem
    curl -XPOST -H 'Content-Type: application/x-pem-file' \
         http://localhost:8080/sign --data-binary @testreq.pem \
         -o testcert.pem
    openssl x509 -in testcert.pem -noout -text
