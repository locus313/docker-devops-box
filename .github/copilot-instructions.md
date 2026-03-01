# Copilot Instructions – docker-devops-box

## What This Project Is

A portable DevOps toolbox delivered as a Docker image (`ghcr.io/locus313/docker-devops-box:latest`). No tools are installed on the host — `run-in-docker.sh` is symlinked to each tool name and transparently proxies execution into the container, mapping the host filesystem automatically.

## Core Files

| File | Role |
|---|---|
| `Dockerfile` | Ubuntu 20.04; all tool installs; non-root `devops` user; zsh + oh-my-zsh; `entrypoint.sh` as `ENTRYPOINT`, default `CMD ["zsh"]` |
| `run-in-docker.sh` | Host launcher: detects tool name via `basename $0`, sources matching `opts/<cmd>`, then runs `docker run -it --rm` |
| `entrypoint.sh` | Container entry: symlinks every dotfile from `/home/$HOST_USER` into `/home/devops` (skips existing), then `exec "$@"` |
| `opts/<name>` | Bash snippet sourced by `run-in-docker.sh`; can set `CMD`, append `DOCKER_OPTS`, define `cleanup()` |

## Execution Flow in run-in-docker.sh

1. `CMD` defaults to `basename $0` (the symlink name), unless already set in the environment.
2. Default `DOCKER_OPTS` are built (hostname, DISPLAY, HOST_USER, docker socket mount).
3. `opts/$CMD` is sourced **before** the `docker run` call — so it can override `CMD` and `DOCKER_OPTS`.
4. Volume strategy is chosen based on `$PWD` (see below), then `docker run -it --rm` executes `cd $REMOTE_PWD && $CMD $ARGS`.
5. After `docker` exits, `cleanup` is called if defined in the sourced opts file.

## The opts/ Pattern

Create `opts/<toolname>` to customise a command's launch without touching `run-in-docker.sh`:

```bash
export CMD=zsh                                              # override binary (default: symlink name)
DOCKER_OPTS="${DOCKER_OPTS} --security-opt seccomp=/tmp/chrome.json"
export DOCKER_OPTS=${DOCKER_OPTS}                          # append docker flags
cleanup() { rm -rf /tmp/chrome.json; }                    # runs after docker exits
```

Examples: `opts/devops-shell` (sets `CMD=zsh`), `opts/run-my-bash` (sets `CMD=bash`), `opts/google-chrome` (downloads seccomp profile + appends flag).

## Volume-Mapping (two modes)

| Context | Host home mount | CWD inside container |
|---|---|---|
| `$PWD` inside `$HOME` | `$HOME → /home/<basename of HOME>` | mirrors host sub-path (full read/write) |
| `$PWD` outside `$HOME` | `$HOME → /host/home/<basename>` (read-only root + writable `$PWD → /host/current`) | `/host/current` |

Set `UNSAFE_WRITE_ROOT=true` to make the host root writable when outside `$HOME`.

## entrypoint.sh Dotfile Behaviour

On every container start, `entrypoint.sh` iterates `ls -a1 /home/$HOST_USER` and symlinks each entry into `/home/devops/`, skipping `.`, `..`, and paths that already exist. This makes host dotfiles (`.ssh`, `.aws`, `.kube`, `.gitconfig`, etc.) available inside the container automatically.

## Build & CI

```bash
docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .   # local build
docker pull ghcr.io/locus313/docker-devops-box:latest               # pull from GHCR
```

`.github/workflows/build.yml`: builds on every push/PR; **pushes only when `github.event_name != 'pull_request'`** (i.e., on merge to `main`). Uses `buildcache` tag for layer caching. Requires repo secret `PAT` (GitHub PAT with `write:packages`).

## Pinned Tool Versions (Dockerfile)

| Tool | Version |
|---|---|
| Terraform (via `tfenv`) | default `1.1.7`; also 0.12.31, 0.13.7, 0.14.11, 0.15.5, 1.0.11 |
| kubectl / kubelet / kubeadm | `1.18.8` (held with `apt-mark hold`) |
| govc | `0.27.4` |
| docker-compose | `1.25.5` |
| Ansible | latest pip3; galaxy collections: `community.aws`, `community.vmware`, `amazon.aws`, etc. |

## Adding a New Tool

1. Add an install block to `Dockerfile` — always end with:
   ```dockerfile
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/* \
   && apt-get autoremove
   ```
2. Create `opts/<toolname>` if the tool needs extra docker flags or a different binary name.
3. Add the symlink to the "Symlink Example" section in `README.md`.

## Adding a New CLI Alias / Symlink

```bash
ln -s $PWD/run-in-docker.sh /usr/local/bin/<toolname>
# To redirect to a different binary: create opts/<toolname> with: export CMD=<actual-binary>
```
