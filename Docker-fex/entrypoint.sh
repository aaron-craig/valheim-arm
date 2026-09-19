#!/usr/bin/env bash
set -Eeuo pipefail

SERVER="/root/valheim-server"
PERSISTENT="/root/.config/unity3d/IronGate/Valheim"
SETTINGS="${PERSISTENT}/settings"

valheim_pid=""
shutdown_requested=0

timestamp() {
    date +"%Y-%m-%d %H:%M:%S,%3N"
}

shutdown() {
    shutdown_requested=1

    echo
    echo "$(timestamp) INFO: Shutdown requested."

    if [[ -n "${valheim_pid}" ]] && kill -0 "${valheim_pid}" 2>/dev/null; then
        echo "$(timestamp) INFO: Sending SIGINT to FEX/Valheim PID ${valheim_pid}"
        kill -INT "${valheim_pid}"
    fi
}

trap shutdown TERM INT

mkdir -p "${SERVER}"
mkdir -p "${SETTINGS}"
mkdir -p "${PERSISTENT}/logs"

echo "========================================"
echo "FEX version"
echo "========================================"
FEXGetConfig --version
echo

echo "========================================"
echo "FEX guest architecture"
echo "========================================"
FEX /usr/bin/uname -m
echo

# Load only FEX_* settings from the persistent emulator config.
if [[ -f "${SETTINGS}/emulators.rc" ]]; then
    echo "$(timestamp) INFO: Loading FEX settings from emulators.rc"

    while IFS='=' read -r key value; do
        [[ "${key}" =~ ^FEX_[A-Za-z0-9_]+$ ]] || continue

        export "${key}=${value}"
        echo "export ${key}=${value}"
    done < <(
        grep -E '^[[:space:]]*FEX_[A-Za-z0-9_]+=' \
            "${SETTINGS}/emulators.rc" |
        sed 's/^[[:space:]]*//'
    )
fi

echo
echo "$(timestamp) INFO: Updating Valheim dedicated server"

export SteamAppId=892970

/usr/local/bin/steamcmd.sh \
    +force_install_dir "${SERVER}" \
    +login anonymous \
    +app_update 896660 \
    +quit

cd "${SERVER}"

CROSSPLAY_FLAG=""

if [[ "${ENABLE_CROSSPLAY:-false}" == "true" ]]; then
    CROSSPLAY_FLAG="-crossplay"
    echo "$(timestamp) INFO: Crossplay enabled."
fi

LOG_FILE="${PERSISTENT}/logs/valheim_$(date '+%Y-%m-%d').log"

echo "$(timestamp) INFO: Starting Valheim under FEX."

FEX ./valheim_server.x86_64 \
    -name "${SERVER_NAME}" \
    -port 2456 \
    -world "${SERVER_WORLD}" \
    -password "${SERVER_PASSWORD}" \
    -public "${SERVER_VISIBILITY:-1}" \
    -saveinterval "${SERVER_SAVE_INTERVAL:-1800}" \
    -backups "${SERVER_BACKUPS:-4}" \
    -backupshort "${SERVER_BACKUP_SHORT:-7200}" \
    -backuplong "${SERVER_BACKUP_LONG:-43200}" \
    -savedir "${PERSISTENT}" \
    ${CROSSPLAY_FLAG:+"${CROSSPLAY_FLAG}"} \
    -nographics \
    -batchmode \
    > >(tee -a "${LOG_FILE}") 2>&1 &

valheim_pid=$!

echo "$(timestamp) INFO: Monitoring FEX/Valheim PID ${valheim_pid}"

set +e
wait "${valheim_pid}"
exit_code=$?
set -e

if [[ "${shutdown_requested}" -eq 1 ]]; then
    echo "$(timestamp) INFO: Valheim exited after requested shutdown."
    exit 0
fi

echo "$(timestamp) ERROR: Valheim exited unexpectedly with code ${exit_code}."
echo "$(timestamp) ERROR: Container will exit so Docker can restart it."

exit 1
