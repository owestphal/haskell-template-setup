FROM fpco/stack-build:lts-14.27 as build
RUN apt-get update && apt-get install -y \
    bbe \
    curl \
    rsync
COPY . /build
WORKDIR /build
RUN for i in $(sed 's/#.*$//' env); do export $i; done \
 && make -e build \
 && make -e install

# FROM ubuntu:18.04 as test
# COPY --from=dependencies /tmp/foobaz /tmp/foobaz
# RUN apt-get update && apt-get install -y \
#     bbe \
#     curl \
#     rsync
# RUN curl -sSL https://get.haskellstack.org/ | sh
# COPY README.md /build/README.md
# COPY ChangeLog.md /build/ChangeLog.md
# COPY Makefile /build/Makefile
# COPY stack.yaml /build/stack.yaml
# COPY package.yaml /build/package.yaml
# WORKDIR /build
# RUN make print
# RUN make all
# CMD ghci -v -package-db /tmp/foobaz/pkgdb
