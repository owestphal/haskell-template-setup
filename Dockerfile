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
