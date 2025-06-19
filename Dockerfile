FROM docker.io/ocaml/opam:alpine
RUN sudo ln -snf /usr/bin/opam-2.3 /usr/bin/opam
RUN opam install --depext-only -y mirage
RUN opam install -y mirage
RUN install -d -m 755 -o opam -g opam ephca
WORKDIR ephca
COPY --chown=opam:opam config.ml ./
RUN opam exec -- mirage configure -t unix
RUN opam exec -- make depends
COPY --chown=opam:opam *.mli *.ml ./
RUN opam exec -- make build

FROM alpine
COPY --from=0 /home/opam/ephca/dist/ephca /usr/local/bin/ephca
RUN apk --no-cache add gmp
EXPOSE 80/tcp
ENTRYPOINT ["/usr/local/bin/ephca"]
