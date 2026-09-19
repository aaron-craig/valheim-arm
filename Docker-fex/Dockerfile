FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Current official Ubuntu 24.04 x86-64 RootFS from FEX.
# Source:
# https://github.com/FEX-Emu/RootFS/blob/main/RootFS_links.json
ARG FEX_ROOTFS_URL="https://rootfs.fex-emu.gg/Ubuntu_24_04/2026-08-11/Ubuntu_24_04.sqsh"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    runx64=FEX \
    XDG_DATA_HOME=/root/.local/share \
    FEX_APP_DATA_LOCATION=/root/.local/share/fex-emu \
    FEX_APP_CONFIG_LOCATION=/root/.fex-emu \
    FEX_ROOTFS=/opt/fex-rootfs/Ubuntu_24_04.sqsh

# ---------------------------------------------------------------------------
# Native ARM64 host dependencies
# ---------------------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        locales \
        lsof \
        procps \
        software-properties-common \
        squashfs-tools \
        libatomic1 \
        libpulse0 \
        libpulse-dev \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# FEX-Emu
#
# Ampere supports ARMv8.2, so use the optimized armv8.2 package.
# The official FEX PPA is updated with FEX releases.
# ---------------------------------------------------------------------------

RUN add-apt-repository -y ppa:fex-emu/fex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        fex-emu-armv8.2 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# FEX x86-64 RootFS
#
# Do not depend on FEXRootFSFetcher to select/configure the RootFS.
# Download the official FEX Ubuntu 24.04 SquashFS image directly and point
# FEX_ROOTFS at an absolute, immutable path.
# ---------------------------------------------------------------------------

RUN mkdir -p \
        /opt/fex-rootfs \
        "${FEX_APP_DATA_LOCATION}" \
        "${FEX_APP_CONFIG_LOCATION}" \
    && curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        "${FEX_ROOTFS_URL}" \
        --output "${FEX_ROOTFS}" \
    && test -s "${FEX_ROOTFS}" \
    && unsquashfs -s "${FEX_ROOTFS}" >/dev/null \
    && printf '{"Config":{"RootFS":"%s"}}\n' "${FEX_ROOTFS}" \
        > "${FEX_APP_CONFIG_LOCATION}/Config.json"

# ---------------------------------------------------------------------------
# Validate native FEX installation.
#
# Do NOT run an x86-64 guest application during the Docker build.
# Guest execution will be verified after the container starts.
# ---------------------------------------------------------------------------

RUN FEXGetConfig --version \
    && command -v FEX \
    && command -v FEXGetConfig \
    && command -v FEXRootFSFetcher \
    && test -f "${FEX_ROOTFS}" \
    && test -f "${FEX_APP_CONFIG_LOCATION}/Config.json"

# ---------------------------------------------------------------------------
# SteamCMD
#
# Valve ships SteamCMD as x86/x86-64 binaries. The wrapper runs it through
# FEX when the container is running.
# ---------------------------------------------------------------------------

RUN mkdir -p /root/steamcmd /root/.steam \
    && curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
        --output /tmp/steamcmd_linux.tar.gz \
    && tar -xzf /tmp/steamcmd_linux.tar.gz -C /root/steamcmd \
    && rm -f /tmp/steamcmd_linux.tar.gz \
    && chmod 0755 /root/steamcmd/steamcmd.sh \
    && printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -e' \
        'exec FEX /root/steamcmd/steamcmd.sh "$@"' \
        > /usr/local/bin/steamcmd \
    && chmod 0755 /usr/local/bin/steamcmd \
    && ln -sf /usr/local/bin/steamcmd /usr/local/bin/steamcmd.sh

# ---------------------------------------------------------------------------
# Valheim container
# ---------------------------------------------------------------------------

WORKDIR /root

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
