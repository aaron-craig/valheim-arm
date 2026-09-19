FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Current official Ubuntu 24.04 x86-64 RootFS from FEX.
ARG FEX_ROOTFS_URL="https://rootfs.fex-emu.gg/Ubuntu_24_04/2026-08-11/Ubuntu_24_04.sqsh"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    runx64=FEX \
    XDG_DATA_HOME=/root/.local/share \
    FEX_APP_DATA_LOCATION=/root/.local/share/fex-emu \
    FEX_APP_CONFIG_LOCATION=/root/.fex-emu \
    FEX_ROOTFS=/opt/fex-rootfs/Ubuntu_24_04

# ---------------------------------------------------------------------------
# Native ARM64 dependencies
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
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# FEX-Emu
#
# Oracle Ampere is ARMv8.2-capable, so use the ARMv8.2 FEX package.
# ---------------------------------------------------------------------------

RUN add-apt-repository -y ppa:fex-emu/fex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        fex-emu-armv8.2 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# FEX x86-64 RootFS
#
# Download the official compressed RootFS during the image build, extract it,
# then delete the SquashFS.
#
# Runtime FEX uses the extracted directory directly. This avoids:
#   - /dev/fuse
#   - SYS_ADMIN
#   - privileged mode
#   - runtime SquashFS mounts
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
        --output /tmp/Ubuntu_24_04.sqsh \
    && echo "=== Validating downloaded RootFS ===" \
    && unsquashfs -s /tmp/Ubuntu_24_04.sqsh \
    && rm -rf "${FEX_ROOTFS}" \
    && echo "=== Extracting FEX RootFS ===" \
    && unsquashfs \
        -f \
        -d "${FEX_ROOTFS}" \
        /tmp/Ubuntu_24_04.sqsh \
    && rm -f /tmp/Ubuntu_24_04.sqsh \
    && test -d "${FEX_ROOTFS}" \
    && test -x "${FEX_ROOTFS}/usr/bin/uname" \
    && echo "=== Extracted RootFS ===" \
    && du -sh "${FEX_ROOTFS}"

# ---------------------------------------------------------------------------
# Validate native FEX installation.
#
# Do not execute an x86-64 guest binary during Docker build. BuildKit can
# impose restrictions that do not exist in the final running container.
# ---------------------------------------------------------------------------

RUN FEXGetConfig --version \
    && command -v FEX \
    && command -v FEXGetConfig \
    && command -v FEXRootFSFetcher \
    && test -d "${FEX_ROOTFS}" \
    && test -x "${FEX_ROOTFS}/usr/bin/uname"
# ---------------------------------------------------------------------------
# x86-64 runtime dependency for PlayFab Party
#
# libparty.so requires libatomic.so.1. The outer container is ARM64, so its
# libatomic1 package is the wrong architecture. Download the Ubuntu 24.04
# amd64 package and extract it directly into the FEX x86-64 RootFS.
# ---------------------------------------------------------------------------

RUN dpkg --add-architecture amd64 \
    && apt-get update \
    && mkdir -p /tmp/amd64-libs \
    && cd /tmp/amd64-libs \
    && apt-get download libatomic1:amd64 \
    && dpkg-deb -x ./libatomic1_*_amd64.deb "${FEX_ROOTFS}" \
    && test -e "${FEX_ROOTFS}/usr/lib/x86_64-linux-gnu/libatomic.so.1" \
    && cd / \
    && rm -rf /tmp/amd64-libs \
    && rm -rf /var/lib/apt/lists/* \
    && dpkg --remove-architecture amd64
    
# ---------------------------------------------------------------------------
# SteamCMD
#
# SteamCMD is x86/x86-64, so the wrapper launches it through FEX.
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
