# docker-devops-box

[![Build](https://github.com/locus313/docker-devops-box/actions/workflows/build.yml/badge.svg)](https://github.com/locus313/docker-devops-box/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A portable DevOps toolbox delivered as a Docker image. No tools are installed on
the host — `run-in-docker.sh` is symlinked to each tool name and transparently
proxies execution into the container, mapping the host filesystem automatically.

---

## Table of Contents

- [Technology Stack](#technology-stack)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Key Features](#key-features)
- [Volume Mapping](#volume-mapping)
- [The opts/ Pattern](#the-opts-pattern)
- [Terraform Version Management](#terraform-version-management)
- [CICD](#cicd)
- [Contributing](#contributing)
- [License](#license)

---

## Technology Stack

### Base Image

| Component | Version |
|---|---|
| Ubuntu | 24.04 LTS |
| Python | 3 (`python3`, `python-is-python3`; no Python 2.7) |
| zsh + oh-my-zsh | latest (bira theme) |

### DevOps Tools

| Tool | Version |
|---|---|
| Terraform (via `tfenv`) | **1.11.2** default; also 0.12.31, 0.14.11, 1.5.7, 1.9.8, 1.10.5 |
| kubectl / kubelet / kubeadm | **1.33** (latest patch via `pkgs.k8s.io`, held) |
| Ansible | Latest via `pip3` |
| Docker CE + Compose v2 | Latest stable |
| AWS CLI v2 | Latest |
| AWS Session Manager Plugin | Latest |
| consul / nomad / packer | Latest (HashiCorp apt repo) |

### Ansible Galaxy Collections (pre-installed)

`community.aws` · `community.azure` · `community.crypto` · `community.general`
· `community.kubernetes` · `community.network` · `community.windows` · `amazon.aws`

---

## Architecture

The project uses a **multi-stage Docker build** to keep the final image lean:

```
┌──────────────────────────────────────────────────────┐
│  Stage 1 — downloader (ubuntu:24.04)                 │
│  Downloads: AWS CLI, Session Manager Plugin,         │
│  tfenv + all pinned Terraform versions               │
└──────────────────┬───────────────────────────────────┘
                   │  COPY --from=downloader
┌──────────────────▼───────────────────────────────────┐
│  Stage 2 — runtime (ubuntu:24.04)                    │
│  Installs: system packages, Python/Ansible,          │
│  Docker CE, Kubernetes tools, HashiCorp tools        │
│  User: devops (non-root, zsh, oh-my-zsh)             │
└──────────────────────────────────────────────────────┘
```

**Host-side execution flow** (`run-in-docker.sh`):

1. Detect the command name from `basename $0` (symlink name).
2. Source `opts/<cmd>` if it exists (may override `CMD` or append `DOCKER_OPTS`).
3. Detect `$PWD` relative to `$HOME` and choose the correct volume-mapping strategy.
4. Run `docker run -it --rm ...` and execute `cd $REMOTE_PWD && $CMD $ARGS` inside the container.
5. Call `cleanup()` from the opts file (if defined) after Docker exits.

**Container startup** (`entrypoint.sh`):

- Iterates `/home/$HOST_USER` and symlinks every dotfile (`.ssh`, `.aws`, `.kube`, `.gitconfig`, etc.) into `/home/devops/`, skipping entries that already exist.
- Calls `exec "$@"` to hand off to the requested command.

---

## Getting Started

### Prerequisites

Docker must be installed and the daemon must be accessible on the host.

```bash
docker info
```

### Pull the Image

```bash
docker pull ghcr.io/locus313/docker-devops-box:latest
```

### Build Locally

```bash
docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .
```

### Create Host CLI Symlinks

Symlink `run-in-docker.sh` to each tool you want to call directly from your
shell. The symlink name determines which binary is executed inside the container.

> **Any binary available inside the container can be proxied** — just create a
> symlink named after it.

---

#### Linux

Ensure the script is executable, then symlink into `/usr/local/bin` (requires
`sudo`) or a user-local directory like `~/.local/bin` (no `sudo` needed).

```bash
# Make the launcher executable (only needed once)
chmod +x run-in-docker.sh

# Option A — system-wide (requires sudo)
BIN_DIR=/usr/local/bin
for tool in ansible ansible-doc ansible-inventory ansible-playbook \
            consul nomad packer terraform devops-shell kubectl; do
  sudo ln -s "$PWD/run-in-docker.sh" "${BIN_DIR}/${tool}"
done

# Option B — current user only (no sudo required)
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
for tool in ansible ansible-doc ansible-inventory ansible-playbook \
            consul nomad packer terraform devops-shell kubectl; do
  ln -s "$PWD/run-in-docker.sh" "${BIN_DIR}/${tool}"
done
# Ensure ~/.local/bin is on your PATH (add to ~/.bashrc or ~/.zshrc if needed):
# export PATH="$HOME/.local/bin:$PATH"
```

---

#### macOS

Docker Desktop for Mac exposes the daemon socket at the default path that
`run-in-docker.sh` expects. The setup is otherwise identical to Linux.

```bash
# Make the launcher executable (only needed once)
chmod +x run-in-docker.sh

# Option A — system-wide (requires sudo; works on Intel and Apple Silicon)
BIN_DIR=/usr/local/bin
for tool in ansible ansible-doc ansible-inventory ansible-playbook \
            consul nomad packer terraform devops-shell kubectl; do
  sudo ln -s "$PWD/run-in-docker.sh" "${BIN_DIR}/${tool}"
done

# Option B — current user only (no sudo required)
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
for tool in ansible ansible-doc ansible-inventory ansible-playbook \
            consul nomad packer terraform devops-shell kubectl; do
  ln -s "$PWD/run-in-docker.sh" "${BIN_DIR}/${tool}"
done
# Ensure ~/.local/bin is on your PATH (add to ~/.zshrc):
# export PATH="$HOME/.local/bin:$PATH"
```

> **macOS note:** If Docker Desktop reports a socket error, confirm the socket
> path in Docker Desktop → Settings → Advanced. The default is
> `/var/run/docker.sock` (a symlink to the user socket).

---

#### WSL on Windows (Recommended approach for Windows users)

**Prerequisites:**

1. [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
   installed with the **WSL 2 backend** enabled.
2. Your WSL distro enabled under Docker Desktop → Settings → Resources → WSL
   Integration.
3. The repository cloned **inside the WSL filesystem** (e.g.
   `~/code/docker-devops-box`) for correct path mapping and best I/O
   performance. Cloning under `/mnt/c/...` works but is significantly slower.

```bash
# Clone into WSL filesystem (if not already done)
git clone https://github.com/locus313/docker-devops-box.git ~/code/docker-devops-box
cd ~/code/docker-devops-box

# Make the launcher executable
chmod +x run-in-docker.sh

# Symlink into ~/.local/bin (no sudo required)
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
for tool in ansible ansible-doc ansible-inventory ansible-playbook \
            consul nomad packer terraform devops-shell kubectl; do
  ln -s "$PWD/run-in-docker.sh" "${BIN_DIR}/${tool}"
done

# Add ~/.local/bin to PATH if not already present (add to ~/.bashrc or ~/.zshrc)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify Docker is reachable from WSL before running any tool:

```bash
docker info
```

> **WSL notes:**
> - Always run the symlinked tools from a **WSL terminal** (e.g. Windows
>   Terminal → Ubuntu), not from PowerShell or CMD — the launcher is a bash
>   script.
> - Your WSL `$HOME` (e.g. `/home/yourname`) is mapped into the container, so
>   dotfiles such as `.ssh`, `.aws`, and `.kube` are available automatically.
> - If you store credentials under the Windows profile (`C:\Users\...`), expose
>   them to WSL by symlinking: `ln -s /mnt/c/Users/$WIN_USER/.aws ~/.aws`

### Drop Into an Interactive Shell

```bash
devops-shell
```

This opens an interactive zsh session inside the container with your host
`$HOME` fully mapped in (including dotfiles like `.ssh`, `.aws`, `.kube`).

---

## Project Structure

```
.
├── Dockerfile          # Multi-stage image build (downloader → runtime)
├── entrypoint.sh       # Container entry: symlinks host dotfiles, then exec "$@"
├── run-in-docker.sh    # Host launcher: detects tool from symlink name, runs docker
├── opts/               # Per-command bash snippets sourced by run-in-docker.sh
│   ├── devops-shell    # Sets CMD=zsh for interactive shell
│   ├── google-chrome   # Downloads seccomp profile; overrides CMD=zsh
│   └── run-my-bash     # Forces CMD=bash
└── .github/
    ├── copilot-instructions.md
    ├── workflows/
    │   └── build.yml   # CI: build, scan, and push to GHCR
    ├── instructions/   # Copilot instruction files
    └── skills/         # Copilot skill prompts
```

---

## Key Features

- **Zero host dependencies** beyond Docker — no Python, Terraform, or kubectl installs needed on the host.
- **Transparent CLI proxy** — symlink `run-in-docker.sh` to any tool name; it just works.
- **Automatic dotfile injection** — host `.ssh`, `.aws`, `.kube`, `.gitconfig`, and other dotfiles are symlinked into the container on every run via `entrypoint.sh`.
- **Multi-version Terraform** — `tfenv` ships with six pre-installed versions; switch instantly with `tfenv use <version>`.
- **Non-root container user** — all commands run as `devops` with `NOPASSWD sudo` for safe file permissions on mapped volumes.
- **Docker-in-Docker** — the Docker socket is always mounted, enabling container management from within the toolbox.
- **Per-command customization** — drop a bash snippet in `opts/<toolname>` to override flags or the executed binary without modifying the launcher script.
- **Container health check** — Docker polls `terraform version`, `kubectl version --client`, and `aws --version` every 60 seconds.

---

## Volume Mapping

The launcher automatically selects a mount strategy based on where you are in the filesystem:

| Context | Host mount | Container path | Write access |
|---|---|---|---|
| Inside `$HOME` | `$HOME` | `/home/<basename of HOME>` | Full read/write |
| Outside `$HOME` | `$HOME` → `/home/<basename>` (read-only) + `$PWD` → `/host/current` (writable) | `/host/current` | User home read-only; `$PWD` writable |

To allow writable host root when outside `$HOME`:

```bash
UNSAFE_WRITE_ROOT=true terraform plan
```

---

## The opts/ Pattern

Create a file at `opts/<toolname>` to customise how that command launches, without modifying `run-in-docker.sh`. Three hooks are available:

```bash
# Override the binary executed in the container (default: symlink basename)
export CMD=zsh

# Append extra Docker flags
DOCKER_OPTS="${DOCKER_OPTS} --security-opt seccomp=/tmp/chrome.json"
export DOCKER_OPTS=${DOCKER_OPTS}

# Optional cleanup function called after docker exits
cleanup() { rm -rf /tmp/chrome.json; }
```

**Example: redirect a symlink to a different binary**

```bash
# opts/my-shell
export CMD=bash
```

```bash
ln -s $PWD/run-in-docker.sh /usr/local/bin/my-shell
my-shell   # drops into bash inside the container
```

---

## Terraform Version Management

`tfenv` manages multiple Terraform versions inside the container.

**Pre-installed versions:** `0.12.31` · `0.14.11` · `1.5.7` · `1.9.8` · `1.10.5` · `1.11.2` (default)

```bash
# List installed versions
devops-shell -c "tfenv list"

# Switch to a different version
devops-shell -c "tfenv use 1.5.7"

# Install an additional version
devops-shell -c "tfenv install 1.2.0"
```

---

## CI/CD

The workflow in [.github/workflows/build.yml](.github/workflows/build.yml) runs on every push and pull request to `main` (markdown-only changes are ignored):

| Event | Behaviour |
|---|---|
| Pull request | Build only (no push) |
| Push to `main` | Build → Grype vulnerability scan → push `latest` + SHA tags to GHCR |

**Registry cache:** `ghcr.io/locus313/docker-devops-box:buildcache` speeds up layer reuse.  
**Security scanning:** [Anchore Grype](https://github.com/anchore/grype) fails the build on any critical CVE; results are uploaded to GitHub Security as SARIF.  
**Required secret:** `PAT` — a GitHub Personal Access Token with `write:packages` and `read:packages` scopes.

---

## Contributing

1. **New tool** — add an install block to `Dockerfile` following the existing pattern (always clean apt caches after); create `opts/<toolname>` if extra Docker flags are needed; add the symlink command to this README.
2. **New alias / symlink** — create `opts/<toolname>` with `export CMD=<actual-binary>` and document the symlink.
3. **Test locally before opening a PR:**
   ```bash
   docker build --rm -t ghcr.io/locus313/docker-devops-box:latest .
   docker run --rm ghcr.io/locus313/docker-devops-box:latest zsh -c "<tool> --version"
   ```
4. Keep PRs focused — one concern per PR (new tool, bug fix, version bump, etc.).
5. Avoid `:latest` tags for pinned tool installs in the Dockerfile — use explicit versions.
6. Ensure `apt-get clean && rm -rf /var/lib/apt/lists/*` follows every `apt-get install` block.

---

## License

This project is licensed under the [MIT License](LICENSE). Copyright (c) 2026 Patrick Lewis.

Originally created by [@nmarus](mailto:nmarus@gmail.com).
