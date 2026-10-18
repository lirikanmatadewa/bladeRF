ARG DEBIAN_SUITE=trixie
FROM debian:${DEBIAN_SUITE}-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        crossbuild-essential-arm64 \
        debhelper \
        devscripts \
        dh-sequence-python3 \
        dpkg-dev \
        doxygen \
        fakeroot \
        file \
        git \
        help2man \
        jq \
        libcurl4-openssl-dev:arm64 \
        libedit-dev:arm64 \
        libncurses-dev:arm64 \
        libusb-1.0-0-dev:arm64 \
        ninja-build \
        pandoc \
        pkg-config \
        python3-all \
        python3-cffi \
        python3-setuptools \
            python3-wheel \
        qemu-user \
        rsync \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/build-in-container.sh"]

COPY build-in-container.sh /usr/local/bin/build-in-container.sh
RUN chmod 0755 /usr/local/bin/build-in-container.sh