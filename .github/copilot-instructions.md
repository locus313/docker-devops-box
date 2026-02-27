# Copilot Instructions – docker-devops-box

## What This Project Is

A portable DevOps toolbox delivered as a Docker image (`ghcr.io/locus313/docker-devops-box:latest`). Host CLI tools (ansible, terraform, kubectl, consul, nomad, packer, AWS CLI, govc, etc.) are **not installed locally** — instead, `run-in-docker.sh` is symlinked to each tool name and transparently runs that tool inside the container.

## Core Architecture

| File | Role |
|---|---|
| `Dockerfile` | Ubuntu 20.04 image; installs all tools; runs as non-root `devops` user with zsh + oh-my-zsh |
| `run-in-docker.sh` | Host-side launcher; reads `basename $0` to determine which container command to run |
| `entrypoint.sh` | Container entry; symlinks host `$HOME` dotfiles into the container user's home |
| `opts/<name>` | Per-command bash snippets sourced by `run-in-docker.sh` to inject extra `DOCKER_OPTS`, override `CMD`, or define `cleanup()` |

## The opts/ Pattern

Adding a file at `opts/<command-name>` customises that command's container launch without touching `run-in-docker.sh`. Three hooks are available:

```bash
# Override which binary runs in the container (default: basename of symlink)
export CMD=zsh

# Append docker flags
DOCKER_OPTS="${DOCKER_OPTS} --security-opt seccomp=/tmp/chrome.json"
export DOCKER_OPTS=${DOCKER_OPTS}

# Optional cleanup function called after docker exits
cleanup() { rm -rf /tmp/chrome.json; }
```

See `opts/devops-shell` (drops into zsh), `opts/google-chrome` (adds seccomp profile), and `opts/run-my-bash` (forces bash) as examples.

## Volume-Mapping Behaviour (two modes)

`run-in-docker.sh` chooses the mount strategy based on `$PWD`:

- **Inside `$HOME`**: maps `$HOME → /home/<basename>`, sets `$REMOTE_PWD` to the equivalent sub-path. Full read/write.
- **Outside `$HOME`**: maps `$HOME → /host/home/<basename>` (user home), mounts `$PWD → /host/current` (writable), and maps host root read-only. Set `UNSAFE_WRITE_ROOT=true` to make host root writable.

## Build & CI

```bash
# Build locally
docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .

# Pull from registry
docker pull ghcr.io/locus313/docker-devops-box:latest
```

CI (`.github/workflows/build.yml`) builds on every push/PR to `main` and pushes to GHCR only on merged commits. Registry cache (`buildcache` tag) speeds up rebuilds.

## Installed Tool Versions (pin points in Dockerfile)

- **Terraform**: managed by `tfenv`; multiple versions installed; default `1.1.7`
- **Kubernetes**: `kubectl`/`kubelet`/`kubeadm` pinned to `1.18.8`
- **govc**: `0.27.4`
- **docker-compose**: `1.25.5`
- **Ansible**: latest pip3 install; galaxy collections include `community.aws`, `community.vmware`, `amazon.aws`, etc.

## Adding a New Tool

1. Add the install block to `Dockerfile` (keep apt cache-clean pattern: `apt-get clean && rm -rf /var/lib/apt/lists/*`).
2. If the tool needs extra docker flags or a different launch command, create `opts/<toolname>`.
3. Document the new symlink in `README.md` under "Symlink Example".

## Adding a New CLI Alias

```bash
ln -s $PWD/run-in-docker.sh /usr/local/bin/<toolname>
# or, for alias-style overrides, create opts/<toolname> with: export CMD=<actual-binary>
```
