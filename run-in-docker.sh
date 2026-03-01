#!/usr/bin/env bash

# ============================================================================
# run-in-docker.sh — Transparent proxy that executes any CLI tool inside the
# docker-devops-box container, mapping the host filesystem automatically.
# Intended to be invoked via a symlink named after the target tool.
# ============================================================================

set -euo pipefail

# Constants
readonly IMAGE="ghcr.io/locus313/docker-devops-box:latest"
readonly DOCKER_HOSTNAME="devops"
readonly CONTAINER_USER="devops"

# Determine command from symlink name unless already set in environment
CMD="${CMD:-$(basename "$0")}"

# Get host IP for X11 config
HOST_IP=$(ifconfig 2>/dev/null \
  | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' \
  | grep -Eo '([0-9]*\.){3}[0-9]*' \
  | grep -v '127.0.0.1' \
  | head -n1 || true)

# Resolve real path to this script (follow symlink)
SCRIPT_PATH="$(dirname "$(readlink "$0")")"

# Build safely-quoted argument list for passing to the container shell
ARGS=''
for i in "$@"; do
  i="${i//\\/\\\\}"
  ARGS="${ARGS} \"${i//\"/\\\"}\""
done

# Default docker opts — per-branch volume mounts are appended below
DOCKER_OPTS="${DOCKER_OPTS:-}"
DOCKER_OPTS="${DOCKER_OPTS} --hostname ${DOCKER_HOSTNAME}"
DOCKER_OPTS="${DOCKER_OPTS} --env DISPLAY=${HOST_IP}:0"
DOCKER_OPTS="${DOCKER_OPTS} --env HOST_USER=$(whoami)"
DOCKER_OPTS="${DOCKER_OPTS} --volume /var/run/docker.sock:/var/run/docker.sock"

# Source per-command opts if present (may override CMD, DOCKER_OPTS, or define cleanup())
if [[ -e "${SCRIPT_PATH}/opts/${CMD}" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_PATH}/opts/${CMD}"
fi

# Run cleanup() defined by an opts file, if any
_run_cleanup() {
  if declare -f cleanup > /dev/null 2>&1; then
    cleanup
  fi
}
trap _run_cleanup EXIT

# Allow docker's exit code to propagate without triggering set -e
set +e

if [[ "${PWD}" == "${HOME}"* ]]; then
  # CWD is inside host $HOME — map the home directory directly
  LOCAL_HOME="${HOME}"
  REMOTE_HOME="/home/$(basename "${HOME}")"
  REMOTE_PWD="${REMOTE_HOME}$(echo "${PWD}" | sed -e "s,^${HOME},,")"

  docker run -it --rm \
    ${DOCKER_OPTS} \
    --volume "${LOCAL_HOME}:${REMOTE_HOME}" \
    "${IMAGE}" sh -c "cd ${REMOTE_PWD} && ${CMD} ${ARGS}"
else
  # CWD is outside $HOME — mount home and expose CWD as /host/current
  LOCAL_HOME="/home/$(basename "${HOME}")"
  REMOTE_HOME="/host"
  REMOTE_PWD="${REMOTE_HOME}/current"
  ROOT_VOL_HOME="/home/$(basename "${HOME}")"
  ROOT_VOL_MAP="${LOCAL_HOME}:${ROOT_VOL_HOME}"

  if [[ "${UNSAFE_WRITE_ROOT:-false}" == "true" ]]; then
    ROOT_VOL_MAP="${LOCAL_HOME}:/"
  fi

  docker run -it --rm \
    ${DOCKER_OPTS} \
    --volume "${ROOT_VOL_MAP}" \
    --volume "${PWD}:${REMOTE_PWD}" \
    "${IMAGE}" sh -c "cd ${REMOTE_PWD} && ${CMD} ${ARGS}"
fi
