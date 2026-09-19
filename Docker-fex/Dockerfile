FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Versions / sources
# ---------------------------------------------------------------------------

# Official FEX Ubuntu 24.04 x86-64 RootFS.
ARG FEX_ROOTFS_URL="https://rootfs.fex-emu.gg/Ubuntu_24_04/2026-08-11/Ubuntu_24_04.sqsh"

# Ubuntu 24.04 amd64 libatomic package required by PlayFab Party.
ARG LIBATOMIC_VERSION="14.2.0-4ubuntu2~24.04.1"

# ---------------------------------------------------------------------------
# Runtime environment
# ---------------------------------------------------------------------------

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
# Oracle Ampere supports ARMv8.2, so use the optimized ARMv8.2 package.
# ---------------------------------------------------------------------------

RUN add-apt-repository -y ppa:fex-emu/fex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        fex-emu-armv8.2 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# FEX x86-64 RootFS
#
# Download the official SquashFS during build, extract it into the image,
# then delete the compressed image.
#
# FEX therefore uses a normal directory at runtime and does NOT require:
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
    && echo "=== Validating FEX RootFS image ===" \
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
    && echo "=== Extracted FEX RootFS ===" \
    && du -sh "${FEX_ROOTFS}"

# ---------------------------------------------------------------------------
# x86-64 libatomic for PlayFab Party
#
# libparty.so is x86-64 and requires libatomic.so.1.
#
# The outer Ubuntu container is ARM64, so its normal libatomic1 package is
# ARM64 and cannot satisfy the PlayFab plugin. Download the official amd64
# Ubuntu package directly and extract it into the FEX guest RootFS.
#
# Do NOT enable amd64 as a host-container dpkg architecture.
# ---------------------------------------------------------------------------

RUN curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        "https://security.ubuntu.com/ubuntu/pool/main/g/gcc-14/libatomic1_${LIBATOMIC_VERSION}_amd64.deb" \
        --output /tmp/libatomic1_amd64.deb \
    && echo "=== Validating libatomic package architecture ===" \
    && test "$(dpkg-deb -f /tmp/libatomic1_amd64.deb Architecture)" = "amd64" \
    && echo "=== Installing x86-64 libatomic into FEX RootFS ===" \
    && dpkg-deb \
        -x \
        /tmp/libatomic1_amd64.deb \
        "${FEX_ROOTFS}" \
    && test -e \
        "${FEX_ROOTFS}/usr/lib/x86_64-linux-gnu/libatomic.so.1" \
    && echo "=== Installed x86-64 libatomic ===" \
    && ls -l \
        "${FEX_ROOTFS}/usr/lib/x86_64-linux-gnu/libatomic.so.1"* \
    && rm -f /tmp/libatomic1_amd64.deb

# ---------------------------------------------------------------------------
# Validate FEX installation
#
# Only validate native ARM64 FEX tools during Docker build.
# Do not launch an x86-64 guest process from BuildKit.
# ---------------------------------------------------------------------------

RUN FEXGetConfig --version \
    && command -v FEX \
    && command -v FEXGetConfig \
    && command -v FEXRootFSFetcher \
    && test -d "${FEX_ROOTFS}" \
    && test -x "${FEX_ROOTFS}/usr/bin/uname" \
    && test -e "${FEX_ROOTFS}/usr/lib/x86_64-linux-gnu/libatomic.so.1"

# ---------------------------------------------------------------------------
# SteamCMD
#
# SteamCMD contains x86/x86-64 binaries. The wrapper runs it through FEX.
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
    && tar \
        -xzf /tmp/steamcmd_linux.tar.gz \
        -C /root/steamcmd \
    && rm -f /tmp/steamcmd_linux.tar.gz \
    && chmod 0755 /root/steamcmd/steamcmd.sh \
    && printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -e' \
        'exec FEX /root/steamcmd/steamcmd.sh "$@"' \
        > /usr/local/bin/steamcmd \
    && chmod 0755 /usr/local/bin/steamcmd \
    && ln -sf \
        /usr/local/bin/steamcmd \
        /usr/local/bin/steamcmd.sh

# ---------------------------------------------------------------------------
# Valheim
# ---------------------------------------------------------------------------

WORKDIR /root

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
