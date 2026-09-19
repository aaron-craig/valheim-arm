#!/bin/bash

SERVER="/root/valheim-server"
PERSISTENT="/root/.config/unity3d/IronGate/Valheim"
SETTINGS="${PERSISTENT}/settings"

shutdown_requested=0
valheim_pid=""
xvfb_pid=""

timestamp () {
    date +"%Y-%m-%d %H:%M:%S,%3N"
}

valheim_alive () {
    if [[ -z "${valheim_pid:-}" ]]; then
        return 1
    fi

    if [[ ! -d "/proc/${valheim_pid}" ]]; then
        return 1
    fi

    # Treat a zombie process as dead.
    local state
    state="$(ps -o stat= -p "${valheim_pid}" 2>/dev/null | tr -d '[:space:]')"

    if [[ -z "${state}" || "${state}" == Z* ]]; then
        return 1
    fi

    return 0
}

shutdown () {
    echo ""
    echo "$(timestamp) INFO: Received shutdown signal, stopping Valheim gracefully"

    shutdown_requested=1

    if valheim_alive; then
        echo "$(timestamp) INFO: Sending SIGINT to Valheim PID ${valheim_pid}"
        kill -2 "${valheim_pid}" 2>/dev/null || true
    else
        echo "$(timestamp) WARN: Valheim process is already stopped"
    fi
}

cleanup () {
    if [[ -n "${xvfb_pid:-}" ]] && kill -0 "${xvfb_pid}" 2>/dev/null; then
        kill "${xvfb_pid}" 2>/dev/null || true
    fi
}

trap shutdown TERM INT
trap cleanup EXIT


echo "Load extra Box64 and FEX-Emu settings from emulators.rc"
source /load_emulators_env.sh
echo ""

/print_app_versions.sh


echo "Update"

export SteamAppId=892970

steamcmd.sh \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER}" \
    +login anonymous \
    +app_update 896660 validate \
    +quit


echo "Checking if BepInEx files need to be copied"

mkdir -p "${SERVER}"

if [[ ! -d "${SERVER}/BepInEx" ]]; then
    echo "Copy BepInEx files"
    cp -r defaults/server/. "${SERVER}/"
else
    echo "The folder ${SERVER}/BepInEx already exists, copying is not needed."
fi

echo ""


echo "Wine configuration"

winetricks sound=disabled


echo "Trying to remove /tmp/.X0-lock"

rm -f /tmp/.X0-lock

echo ""


echo "Starting Xvfb"

Xvfb :0 -screen 0 1024x768x16 &
xvfb_pid=$!

sleep 5


echo "Starting server"
echo ""

cd "${SERVER}" || exit 1


if [[ ! -f "${SERVER}/linux64/libpulse-mainloop-glib.so.0" ]]; then
    echo "Installing libpulse-mainloop-glib.so.0:x86_64"

    mkdir -p "${SERVER}/linux64/"

    temp_dir="$(mktemp -d)"
    pushd "${temp_dir}" >/dev/null || exit 1

    wget \
        http://mirrors.edge.kernel.org/ubuntu/pool/main/p/pulseaudio/libpulse-mainloop-glib0_17.0%2Bdfsg1-2ubuntu3_amd64.deb

    dpkg -x \
        libpulse-mainloop-glib0_17.0+dfsg1-2ubuntu3_amd64.deb \
        ./

    cp \
        usr/lib/x86_64-linux-gnu/libpulse-mainloop-glib.so.0 \
        "${SERVER}/linux64/"

    popd >/dev/null || exit 1
    rm -rf "${temp_dir}"

    echo "Installing libpulse-mainloop-glib.so.0:x86_64 - Done"
fi


sed -i \
    "s/^enabled *=.*/enabled = ${ENABLE_PLUGINS}/" \
    "${SERVER}/doorstop_config.ini"


if [[ "${ENABLE_PLUGINS}" == "true" ]]; then
    echo "Plugins support is ENABLED"
    export WINEDLLOVERRIDES="winhttp=n,b"
else
    echo "Plugins support is DISABLED"
fi


if [[ "${ENABLE_CROSSPLAY}" == "true" ]]; then
    echo "Crossplay is ENABLED"
    CROSSPLAY_FLAG="-crossplay"
else
    echo "Crossplay is DISABLED"
    CROSSPLAY_FLAG=""
fi


mkdir -p "${PERSISTENT}/logs"

LOG_FILE="${PERSISTENT}/logs/valheim_$(date '+%d-%m-%Y').log"


echo "$(timestamp) INFO: Launching Valheim"

wine valheim_server.exe \
    -name "${SERVER_NAME}" \
    -port 2456 \
    -world "${SERVER_WORLD}" \
    -password "${SERVER_PASSWORD}" \
    -public "${SERVER_VISIBILITY}" \
    -saveinterval "${SERVER_SAVE_INTERVAL}" \
    -backups "${SERVER_BACKUPS}" \
    -backupshort "${SERVER_BACKUP_SHORT}" \
    -backuplong "${SERVER_BACKUP_LONG}" \
    -savedir "${PERSISTENT}" \
    ${CROSSPLAY_FLAG:+"${CROSSPLAY_FLAG}"} \
    -nographics \
    -batchmode \
    2>&1 | tee -a "${LOG_FILE}" &


#
# Find the actual Valheim server PID.
#

timeout=0

while [[ ${timeout} -lt 11 ]]; do
    valheim_pid="$(pgrep -f '[v]alheim_server.exe' | head -n 1 || true)"

    if [[ -n "${valheim_pid}" ]]; then
        echo "$(timestamp) INFO: Valheim server started with PID ${valheim_pid}"
        break
    fi

    if [[ ${timeout} -eq 10 ]]; then
        echo "$(timestamp) ERROR: Timed out waiting for valheim_server.exe"
        exit 1
    fi

    sleep 6
    ((timeout++))

    echo "$(timestamp) INFO: Waiting for valheim_server.exe to start"
done


echo ""
echo "Checking NTSYNC"
echo "The NTSYNC module has been present in the Linux kernel since version 6.14."
echo "Kernel version on this machine is -- $(uname -r)"
echo ""

/usr/bin/lsof /dev/ntsync 2>/dev/null || true

echo ""

if /sbin/lsmod | grep -q ntsync; then
    if /usr/bin/lsof /dev/ntsync >/dev/null 2>&1; then
        echo "NTSYNC module is present and ntsync is running."
    else
        echo "NTSYNC module is present, but ntsync is not running."
        echo "No problem — ntsync is not required."
    fi
else
    echo "NTSYNC module is not present."
    echo "No problem — ntsync is not required."
fi

echo ""


#
# IMPORTANT:
# Monitor VALHEIM itself rather than waiting for every background process.
#
# Previously a Valheim crash left Xvfb alive, which kept the Docker
# container running indefinitely. Docker therefore had no container exit
# to which restart: unless-stopped could respond.
#

echo "$(timestamp) INFO: Monitoring Valheim server PID ${valheim_pid}"

while valheim_alive; do
    sleep 5
done


#
# Valheim has stopped.
#

if [[ "${shutdown_requested}" -eq 1 ]]; then
    echo "$(timestamp) INFO: Valheim exited after requested shutdown."
    echo "$(timestamp) INFO: Shutdown complete."
    exit 0
fi


echo "$(timestamp) ERROR: Valheim server exited unexpectedly."
echo "$(timestamp) ERROR: Container will exit with status 1 so Docker can restart it."

exit 1
