#!/usr/bin/env bash
set -Eeuo pipefail

SERVER="/root/valheim-server"
PERSISTENT="/root/.config/unity3d/IronGate/Valheim"
SETTINGS="${PERSISTENT}/settings"
LOG_DIR="${PERSISTENT}/logs"

valheim_pid=""
shutdown_requested=0

timestamp() {
    date +"%Y-%m-%d %H:%M:%S,%3N"
}

process_alive() {
    [[ -n "${valheim_pid}" ]] || return 1
    [[ -r "/proc/${valheim_pid}/stat" ]] || return 1

    local state
    state="$(ps -o stat= -p "${valheim_pid}" 2>/dev/null | tr -d '[:space:]')"

    [[ -n "${state}" ]] || return 1
    [[ "${state:0:1}" != "Z" ]]
}

shutdown() {
    shutdown_requested=1

    echo
    echo "$(timestamp) INFO: Shutdown requested."

    if process_alive; then
        echo "$(timestamp) INFO: Sending SIGINT to FEX/Valheim PID ${valheim_pid}"
        kill -INT "${valheim_pid}" 2>/dev/null || true
    fi
}

trap shutdown TERM INT

# ---------------------------------------------------------------------------
# Server defaults / validation
# ---------------------------------------------------------------------------

SERVER_NAME="${SERVER_NAME:-Valheim_Server}"
SERVER_WORLD="${SERVER_WORLD:-tsx_world}"
SERVER_VISIBILITY="${SERVER_VISIBILITY:-1}"
SERVER_SAVE_INTERVAL="${SERVER_SAVE_INTERVAL:-1800}"
SERVER_BACKUPS="${SERVER_BACKUPS:-4}"
SERVER_BACKUP_SHORT="${SERVER_BACKUP_SHORT:-7200}"
SERVER_BACKUP_LONG="${SERVER_BACKUP_LONG:-43200}"
ENABLE_CROSSPLAY="${ENABLE_CROSSPLAY:-false}"

if [[ -z "${SERVER_PASSWORD:-}" ]]; then
    echo "$(timestamp) ERROR: SERVER_PASSWORD is not set."
    exit 1
fi

if (( ${#SERVER_PASSWORD} < 5 )); then
    echo "$(timestamp) ERROR: SERVER_PASSWORD must be at least 5 characters."
    exit 1
fi

for var in \
    SERVER_SAVE_INTERVAL \
    SERVER_BACKUPS \
    SERVER_BACKUP_SHORT \
    SERVER_BACKUP_LONG
do
    value="${!var}"

    if ! [[ "${value}" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
        echo "$(timestamp) ERROR: ${var} must be a positive integer. Current value: ${value}"
        exit 1
    fi
done

if ! [[ "${SERVER_VISIBILITY}" =~ ^[01]$ ]]; then
    echo "$(timestamp) ERROR: SERVER_VISIBILITY must be 0 or 1."
    exit 1
fi

mkdir -p \
    "${SERVER}" \
    "${SETTINGS}" \
    "${LOG_DIR}"

# ---------------------------------------------------------------------------
# FEX configuration
# ---------------------------------------------------------------------------

# Load user-provided FEX tuning variables.
#
# Do not permit emulators.rc to replace the RootFS/config paths baked into
# the image. Those are part of the container runtime itself.
if [[ -f "${SETTINGS}/emulators.rc" ]]; then
    echo "$(timestamp) INFO: Loading FEX settings from emulators.rc"

    while IFS='=' read -r key value; do
        [[ "${key}" =~ ^FEX_[A-Za-z0-9_]+$ ]] || continue

        case "${key}" in
            FEX_ROOTFS|FEX_APP_DATA_LOCATION|FEX_APP_CONFIG_LOCATION)
                echo "$(timestamp) WARNING: Ignoring protected setting ${key}"
                continue
                ;;
        esac

        export "${key}=${value}"
        echo "export ${key}=${value}"

    done < <(
        grep -E '^[[:space:]]*FEX_[A-Za-z0-9_]+=' \
            "${SETTINGS}/emulators.rc" 2>/dev/null \
            | sed 's/^[[:space:]]*//' \
            || true
    )
fi

echo
echo "========================================"
echo "FEX version"
echo "========================================"

FEXGetConfig --version

echo
echo "========================================"
echo "FEX RootFS"
echo "========================================"

if [[ -z "${FEX_ROOTFS:-}" ]]; then
    echo "$(timestamp) ERROR: FEX_ROOTFS is not configured."
    exit 1
fi

if [[ ! -r "${FEX_ROOTFS}" ]]; then
    echo "$(timestamp) ERROR: FEX RootFS does not exist or is not readable:"
    echo "${FEX_ROOTFS}"
    exit 1
fi

echo "RootFS: ${FEX_ROOTFS}"
ls -lh "${FEX_ROOTFS}"

echo
echo "========================================"
echo "FEX guest architecture"
echo "========================================"

guest_arch="$(FEX /usr/bin/uname -m)"

echo "${guest_arch}"

if [[ "${guest_arch}" != "x86_64" ]]; then
    echo "$(timestamp) ERROR: FEX guest architecture is '${guest_arch}', expected x86_64."
    exit 1
fi

echo
echo "$(timestamp) INFO: FEX runtime validation successful."

# ---------------------------------------------------------------------------
# SteamCMD / Valheim update
# ---------------------------------------------------------------------------

echo
echo "$(timestamp) INFO: Updating Valheim dedicated server."

export SteamAppId=892970

/usr/local/bin/steamcmd \
    +force_install_dir "${SERVER}" \
    +login anonymous \
    +app_update 896660 \
    +quit

if [[ "${shutdown_requested}" -eq 1 ]]; then
    echo "$(timestamp) INFO: Shutdown was requested during update. Not starting Valheim."
    exit 0
fi

if [[ ! -x "${SERVER}/valheim_server.x86_64" ]]; then
    echo "$(timestamp) ERROR: Valheim server binary was not installed:"
    echo "${SERVER}/valheim_server.x86_64"
    exit 1
fi

# Valheim ships additional x86-64 libraries here.
export LD_LIBRARY_PATH="${SERVER}/linux64:${LD_LIBRARY_PATH:-}"

cd "${SERVER}"

# ---------------------------------------------------------------------------
# Runtime arguments
# ---------------------------------------------------------------------------

EXTRA_ARGS=()

if [[ "${ENABLE_CROSSPLAY}" == "true" ]]; then
    EXTRA_ARGS+=("-crossplay")
    echo "$(timestamp) INFO: Crossplay enabled."
else
    echo "$(timestamp) INFO: Crossplay disabled."
fi

LOG_FILE="${LOG_DIR}/valheim_$(date '+%Y-%m-%d').log"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

echo
echo "$(timestamp) INFO: Starting Valheim under FEX."

FEX ./valheim_server.x86_64 \
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
    "${EXTRA_ARGS[@]}" \
    -nographics \
    -batchmode \
    > >(tee -a "${LOG_FILE}") 2>&1 &

valheim_pid=$!

echo "$(timestamp) INFO: Monitoring FEX/Valheim PID ${valheim_pid}"

# ---------------------------------------------------------------------------
# Supervision
# ---------------------------------------------------------------------------

set +e
wait "${valheim_pid}"
exit_code=$?
set -e

if [[ "${shutdown_requested}" -eq 1 ]]; then
    echo "$(timestamp) INFO: Waiting for Valheim to finish graceful shutdown."

    while process_alive; do
        sleep 1
    done

    wait "${valheim_pid}" 2>/dev/null || true

    echo "$(timestamp) INFO: Valheim shutdown complete."
    exit 0
fi

echo "$(timestamp) ERROR: Valheim exited unexpectedly with code ${exit_code}."
echo "$(timestamp) ERROR: Container will exit with status 1 so Docker can restart it."

exit 1
