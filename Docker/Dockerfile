FROM tsxcloud/steamcmd-wine-ntsync:10.20-arm64-box@sha256:623c85deed796bb37a718552b50bb98c8cb77901d6b6af4e01eeba9cb89da472

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends --only-upgrade box64 \
    && box64 --version \
    && ! box64 --version 2>&1 | grep -q 'v0\.3\.9' \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

COPY server/ defaults/server/

COPY emulators.rc .

COPY --chmod=0755 load_emulators_env.sh /load_emulators_env.sh
COPY --chmod=0755 print_app_versions.sh /print_app_versions.sh
COPY --chmod=0755 entrypoint.sh /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
