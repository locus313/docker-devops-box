#!/usr/bin/env bash

# ============================================================================
# entrypoint.sh - Container entrypoint
# Symlinks host user dotfiles into the container user's home directory,
# then exec's the provided command.
# ============================================================================

set -euo pipefail

# fix docker socket permissions in container
# sudo chown root:docker /var/run/docker.sock 2>/dev/null
# sudo chmod 644 /var/run/docker.sock 2>/dev/null

# Link files from host user home volume into container user home volume
if [[ -d "/home/${HOST_USER}" ]]; then
  while IFS= read -r -d '' homepath; do
    basename_path="$(basename "${homepath}")"
    # Skip files that already exist in the container user's home directory
    if [[ ! -e "/home/${CONTAINER_USER}/${basename_path}" ]]; then
      ln -s "${homepath}" "/home/${CONTAINER_USER}/${basename_path}" 2>/dev/null || true
    fi
  done < <(find "/home/${HOST_USER}" -maxdepth 1 -mindepth 1 -print0)
fi

# Install additional Terraform versions requested at runtime.
# Usage: docker run -e TFENV_VERSIONS="1.5.7 1.9.8" ...
if [[ -n "${TFENV_VERSIONS:-}" ]]; then
  for tf_version in ${TFENV_VERSIONS}; do
    tfenv install "${tf_version}"
  done
fi

exec "$@"
