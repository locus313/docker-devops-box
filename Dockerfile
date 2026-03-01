# =============================================================================
# Stage 1: downloader
# Fetches and prepares all external binary artifacts so that download
# intermediaries (zip files, installers, git history) never appear in the
# final image layers.
# =============================================================================
FROM ubuntu:24.04 AS downloader

ARG K8S_VERSION=1.33

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
  && apt-get update \
  && apt-get install -yq --no-install-recommends \
    ca-certificates curl git gnupg lsb-release unzip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# --- AWS CLI v2 ---
# Install to /usr/local/aws-cli so absolute-path symlinks remain valid after COPY.
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
  && unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2 \
  && /tmp/awscliv2/aws/install --install-dir /usr/local/aws-cli --bin-dir /tmp/aws-bin \
  && rm -rf /tmp/awscliv2.zip /tmp/awscliv2

# --- AWS Session Manager Plugin ---
RUN curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
    -o /opt/session-manager-plugin.deb

# --- tfenv + latest Terraform version ---
# Only the latest stable release is baked into the image at build time.
# Additional versions can be installed at container startup via the
# TFENV_VERSIONS environment variable (space-separated list, e.g.
# TFENV_VERSIONS="1.5.7 1.9.8").
RUN git clone --depth=1 https://github.com/tfutils/tfenv.git /usr/local/tfenv \
  && ln -s /usr/local/tfenv/bin/tfenv     /usr/local/bin/tfenv \
  && ln -s /usr/local/tfenv/bin/terraform /usr/local/bin/terraform \
  && tfenv install latest \
  && tfenv use latest

# =============================================================================
# Stage 2: runtime
# Lean final image containing only what is needed to run the DevOps toolbox.
# Build-time download artifacts never appear in this layer graph.
# =============================================================================
FROM ubuntu:24.04 AS runtime

LABEL org.opencontainers.image.source=https://github.com/locus313/docker-devops-box

ARG LOCAL_USER=devops
ARG K8S_VERSION=1.33

ENV CONTAINER_USER=${LOCAL_USER} \
    TERM=xterm \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# --- System packages, locale, and Python ---
# Combined into one layer to reduce image size and maximise cache reuse.
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
  && apt-get update \
  && apt-get install -yq --no-install-recommends \
    apt-utils apt-transport-https \
    ca-certificates gnupg lsb-release \
    locales \
    sudo man wget nano curl git git-core gitk \
    vim uuid-runtime gawk zip unzip gzip rsync diffstat chrpath \
    software-properties-common iputils-ping net-tools \
    xterm fonts-powerline zsh \
    python3 python3-pip python-is-python3 \
  && apt-get upgrade -yq \
  && locale-gen en_US.UTF-8 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# --- Python libraries and Ansible ---
RUN pip3 install --no-cache-dir --upgrade --break-system-packages \
  argcomplete \
  paramiko \
  setuptools \
  requests \
  pywinrm \
  six \
  boto \
  boto3 \
  botocore \
  docker \
  jsondiff \
  PyYAML \
  ansible

# --- Docker CE + Compose plugin ---
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -yq --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-compose-plugin \
  && ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# --- Kubernetes tools (kubectl / kubelet / kubeadm) ---
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list \
  && apt-get update \
  && apt-get install -yq --no-install-recommends kubelet kubeadm kubectl \
  && apt-mark hold kubelet kubeadm kubectl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# --- HashiCorp tools (consul, nomad, packer) ---
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list \
  && apt-get update \
  && apt-get install -yq --no-install-recommends consul nomad packer \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# --- Artifacts from downloader stage ---
# AWS CLI: copy the installation directory; symlinks inside use the same
# absolute path (/usr/local/aws-cli), so they resolve correctly after COPY.
COPY --from=downloader /usr/local/aws-cli /usr/local/aws-cli
RUN ln -sf /usr/local/aws-cli/v2/current/bin/aws             /usr/local/bin/aws \
  && ln -sf /usr/local/aws-cli/v2/current/bin/aws_completer  /usr/local/bin/aws_completer

# Session Manager plugin
COPY --from=downloader /opt/session-manager-plugin.deb /tmp/session-manager-plugin.deb
RUN dpkg -i /tmp/session-manager-plugin.deb \
  && rm -f /tmp/session-manager-plugin.deb

# tfenv + pre-downloaded Terraform version (latest at build time)
COPY --from=downloader /usr/local/tfenv /usr/local/tfenv
RUN ln -s /usr/local/tfenv/bin/tfenv     /usr/local/bin/tfenv \
  && ln -s /usr/local/tfenv/bin/terraform /usr/local/bin/terraform \
  && tfenv use latest

# --- Entrypoint (single COPY with mode; no separate chmod layer) ---
COPY --chmod=0755 entrypoint.sh /entrypoint.sh

# --- Vim preferences for root ---
RUN printf 'syntax on\nset number\n' > /root/.vimrc

# --- Non-root user setup (consolidated into one layer) ---
# Docker CE is already installed at this point, so the docker group exists.
RUN groupadd -r ${LOCAL_USER} \
  && useradd --no-log-init -m -s /bin/zsh \
      -g ${LOCAL_USER} \
      -G audio,video,docker,sudo \
      ${LOCAL_USER} \
  && mkdir -p /home/${LOCAL_USER}/Downloads \
  && chown -R ${LOCAL_USER}:${LOCAL_USER} /home/${LOCAL_USER} \
  && echo "${LOCAL_USER}:${LOCAL_USER}" | chpasswd \
  && echo "${LOCAL_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER ${LOCAL_USER}
WORKDIR /home/${LOCAL_USER}

# --- Vim preferences for user ---
RUN printf 'syntax on\nset number\n' > /home/${LOCAL_USER}/.vimrc

# --- Oh-my-zsh + zshrc config (single layer) ---
RUN wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | zsh || true \
  && sed -i 's/^ZSH_THEME=.*/ZSH_THEME="bira"/g'                    /home/${LOCAL_USER}/.zshrc \
  && sed -i 's/^plugins=.*/plugins=(git python ansible terraform)/g' /home/${LOCAL_USER}/.zshrc

# --- Terraform shell autocomplete ---
RUN terraform -install-autocomplete

# --- Ansible Galaxy collections (required for Ansible 2.10+) ---
RUN ansible-galaxy collection install \
  community.aws \
  community.azure \
  community.crypto \
  community.general \
  community.kubernetes \
  community.network \
  community.windows \
  amazon.aws

HEALTHCHECK --interval=60s --timeout=15s --start-period=10s --retries=3 \
  CMD terraform version > /dev/null && kubectl version --client > /dev/null && aws --version > /dev/null

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "zsh" ]
