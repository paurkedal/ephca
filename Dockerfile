FROM ocaml/opam:alpine-ocaml-4.12
RUN eval $(opam env); opam depext -y mirage
RUN eval $(opam env); opam install -y mirage
RUN install -d -m 755 -o opam -g opam ephca
WORKDIR ephca
COPY --chown=opam:opam config.ml ./
RUN eval $(opam env); mirage configure -t unix
RUN eval $(opam env); opam depext -y conf-gmp
RUN eval $(opam env); opam install -y --deps-only .
COPY --chown=opam:opam *.mli *.ml ./
RUN eval $(opam env); opam install -y .
RUN eval $(opam env); ln -snf $(dirname $(type -p ephca)) _installed_bin

FROM alpine
COPY --from=0 /home/opam/ephca/_installed_bin/ephca /usr/local/bin/ephca
RUN apk --no-cache add gmp
EXPOSE 80/tcp
ENTRYPOINT /usr/local/bin/ephca
