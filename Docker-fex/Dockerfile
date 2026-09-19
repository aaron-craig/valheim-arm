FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    runx64=FEX

# Native ARM64 runtime + FEX prerequisites
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        software-properties-common \
        squashfs-tools \
        locales \
        procps \
        lsof \
        libatomic1 \
        libpulse0 \
        dpkg-dev \
    && locale-gen en_US.UTF-8 \
    && add-apt-repository -y ppa:fex-emu/fex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        fex-emu-armv8.2 \
    && rm -rf /var/lib/apt/lists/*

# Install the official Ubuntu 24.04 x86-64 RootFS for FEX.
RUN mkdir -p /root/.fex-emu/RootFS \
    && FEXRootFSFetcher \
         -y -x \
         --distro-name=ubuntu \
         --distro-version=24.04

# Fail the build if FEX itself isn't functional.
RUN FEX --version \
    && FEX /usr/bin/uname -m | grep -qx x86_64

# Install current SteamCMD.
RUN mkdir -p /root/steamcmd \
    && curl -fsSL \
       https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /root/steamcmd \
    && printf '%s\n' \
       '#!/bin/bash' \
       'exec FEX /root/steamcmd/steamcmd.sh "$@"' \
       > /usr/local/bin/steamcmd.sh \
    && chmod 0755 /usr/local/bin/steamcmd.sh \
    && /usr/local/bin/steamcmd.sh +quit

WORKDIR /root

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
