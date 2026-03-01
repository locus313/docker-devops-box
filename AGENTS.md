# AGENTS.md

## Project Overview

**docker-devops-box** is a portable DevOps toolbox delivered as a Docker image (`ghcr.io/locus313/docker-devops-box:latest`). Rather than installing CLI tools on the host, `run-in-docker.sh` is symlinked to each tool name and transparently proxies execution into the container, mapping the host filesystem automatically.

**Base image:** Ubuntu 20.04  
**Container user:** `devops` (non-root, runs zsh + oh-my-zsh)  
**Registry:** GitHub Container Registry (`ghcr.io/locus313/docker-devops-box`)

### Installed Tools

| Tool | Version / Notes |
|---|---|
| Terraform | Managed by `tfenv`; default `1.1.7` (also: 0.12.31, 0.13.7, 0.14.11, 0.15.5, 1.0.11) |
| kubectl / kubelet / kubeadm | `1.32` (latest patch; installed from `pkgs.k8s.io`) |
| Ansible | Latest via `pip3`; galaxy collections pre-installed |
| docker-compose | `1.25.5` |
| AWS CLI v2 | Latest |
| AWS Session Manager plugin | Latest |
| consul / nomad / packer | Latest via HashiCorp apt repo |
| Python | Python 3.8 (preferred), Python 2.7 (fallback) |

### Ansible Galaxy Collections (pre-installed)

`community.aws`, `community.azure`, `community.crypto`, `community.general`,
`community.kubernetes`, `community.network`, `community.windows`, `amazon.aws`

---

## Repository Structure

```
Dockerfile          # Image definition; installs all tools; runs as non-root devops user
entrypoint.sh       # Container entrypoint; symlinks host $HOME dotfiles into container home
run-in-docker.sh    # Host-side launcher; reads basename $0 to determine container command
local.conf          # Fonts config (used by commented-out X11 features)
opts/               # Per-command bash snippets sourced by run-in-docker.sh
  devops-shell      # Drops into interactive zsh shell
  google-chrome     # Adds seccomp profile; overrides CMD to zsh
  run-my-bash       # Forces CMD=bash
.github/
  workflows/
    build.yml       # CI: builds and pushes image to GHCR on push to main
  instructions/     # Copilot instruction files for various domains
  skills/           # Copilot skill prompts
```

---

## Setup and Prerequisites

The host only needs Docker installed and accessible.

```bash
# Verify Docker is available on the host
docker info
```

### Pull the Image

```bash
docker pull ghcr.io/locus313/docker-devops-box:latest
```

### Build the Image Locally

```bash
docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .
```

### Create Host CLI Symlinks

Symlink `run-in-docker.sh` to each tool name you want to use on the host:

```bash
BIN_DIR=/usr/local/bin
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/ansible
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/ansible-doc
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/ansible-inventory
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/ansible-playbook
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/consul
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/nomad
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/packer
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/terraform
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/devops-shell
ln -s $PWD/run-in-docker.sh ${BIN_DIR}/kubectl
```

Any executable available inside the container can be proxied this way — just symlink `run-in-docker.sh` to any name in `$PATH`.

---

## Development Workflow

### Drop Into an Interactive Shell

```bash
devops-shell
```

This opens a zsh session inside the container with host `$HOME` mapped in.

### Run a Specific Tool

Once symlinked, invoke tools as if they were locally installed:

```bash
terraform --version
ansible --version
kubectl version --client
aws --version
```

---

## The `opts/` Pattern

Creating a file at `opts/<command-name>` customises that command's container launch without modifying `run-in-docker.sh`. Three hooks are available:

```bash
# Override which binary executes in the container (default: basename of the symlink)
export CMD=zsh

# Append extra docker flags
DOCKER_OPTS="${DOCKER_OPTS} --security-opt seccomp=/tmp/chrome.json"
export DOCKER_OPTS=${DOCKER_OPTS}

# Optional cleanup function called after docker exits
cleanup() { rm -rf /tmp/chrome.json; }
```

**Examples:**
- `opts/devops-shell` — sets `CMD=zsh` for an interactive shell
- `opts/google-chrome` — downloads a seccomp profile and appends it to `DOCKER_OPTS`
- `opts/run-my-bash` — forces `CMD=bash`

To add a new alias or override, create `opts/<toolname>` with the appropriate exports.

---

## Volume-Mapping Behaviour

`run-in-docker.sh` chooses the mount strategy based on `$PWD`:

| Context | Host mount | Container path | Notes |
|---|---|---|---|
| Inside `$HOME` | `$HOME` | `/home/<basename>` | Full read/write; `$REMOTE_PWD` mirrors sub-path |
| Outside `$HOME` | `$HOME` | `/host/home/<basename>` | User home mapped; `$PWD` → `/host/current` (writable); host root read-only |

To allow writable host root when outside `$HOME`:

```bash
UNSAFE_WRITE_ROOT=true <tool> [args]
```

---

## Adding a New Tool

1. Add the install block to `Dockerfile`. Follow the existing pattern — clean apt caches after each `apt-get install`:
   ```dockerfile
   RUN apt-get update \
     && apt-get install -yq <package> \
     && apt-get clean \
     && rm -rf /var/lib/apt/lists/* \
     && apt-get autoremove
   ```
2. If the tool needs extra Docker flags or a different launch command, create `opts/<toolname>`.
3. Add the symlink command to the "Symlink Example" section in `README.md`.

---

## Build and CI/CD

The workflow in `.github/workflows/build.yml` runs on every push and pull request targeting `main`:

- **On PRs**: builds the image only (no push).
- **On merge to `main`**: builds and pushes `ghcr.io/locus313/docker-devops-box:latest` to GHCR.
- **Registry cache**: uses `ghcr.io/locus313/docker-devops-box:buildcache` to speed up rebuilds.
- **Skipped for**: changes to `**/*.md` files (`paths-ignore`).

**Required secret:** `PAT` — a GitHub Personal Access Token with `write:packages` and `read:packages` scopes, stored in repository secrets.

To build and test locally before pushing:

```bash
docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .
docker run --rm -it ghcr.io/locus313/docker-devops-box:latest zsh -c "terraform --version && ansible --version && kubectl version --client"
```

---

## Terraform Version Management

`tfenv` manages multiple Terraform versions inside the container:

```bash
# List installed versions
tfenv list

# Switch active version (run inside devops-shell or via terraform symlink)
tfenv use 0.14.11

# Install an additional version
tfenv install 1.2.0
```

Current default: `1.1.7`

Available pre-installed: `0.12.31`, `0.13.7`, `0.14.11`, `0.15.5`, `1.0.11`, `1.1.7`

---

## Security Notes

- The container runs as non-root user `devops` with `NOPASSWD sudo`.
- The Docker socket (`/var/run/docker.sock`) is always mounted, allowing Docker-in-Docker operations.
- `UNSAFE_WRITE_ROOT=true` should only be set when write access to the host root is explicitly required.
- Do not bake secrets or credentials into `Dockerfile` or `opts/` files. Use environment variables or mounted credential files instead.
- Container images use Ubuntu 20.04 — periodically review and update base image and tool versions for security patches.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `docker: Cannot connect to the Docker daemon` | Ensure Docker daemon is running on the host: `docker info` |
| Tool not found after symlinking | Confirm the symlink points to `run-in-docker.sh` and the name matches a binary in the container |
| Permission denied on host files | Files outside `$HOME` are read-only by default; set `UNSAFE_WRITE_ROOT=true` if write access is needed |
| `cleanup` not running after exit | Ensure `cleanup()` is defined (not just referenced) in the relevant `opts/<name>` file |
| X11 / GUI tools not working | X11 features are commented out in the Dockerfile; re-enable and configure `DISPLAY` as needed |
| Wrong Terraform version | Run `tfenv use <version>` inside `devops-shell` |

---

## Pull Request Guidelines

- Keep changes focused: one concern per PR (new tool, bug fix, version bump, etc.)
- For new tools, always include: Dockerfile install block + optional `opts/<name>` + README symlink entry
- Avoid `:latest` tags for pinned tool installs in the Dockerfile — use explicit versions
- Ensure `apt-get clean && rm -rf /var/lib/apt/lists/*` follows every `apt-get install` block
- Test the image locally before opening a PR:
  ```bash
  docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .
  docker run --rm ghcr.io/locus313/docker-devops-box:latest zsh -c "<tool> --version"
  ```
