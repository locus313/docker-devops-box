FROM ubuntu:24.04

LABEL org.opencontainers.image.source https://github.com/locus313/docker-devops-box

ARG LOCAL_USER=devops
ARG LOCAL_PASS=devops

ENV CONTAINER_USER ${LOCAL_USER}
ENV TERM xterm

# setup apt
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get update \
  && apt-get install -yq apt-utils \
  && apt-get upgrade -yq \
  && apt-get install -yq \
    software-properties-common locales iputils-ping net-tools vim uuid-runtime \
    sudo man wget nano curl git gawk zip unzip gzip xterm git git-core gitk \
    rsync diffstat zsh chrpath fonts-powerline ca-certificates \
    apt-transport-https gnupg-agent lsb-release \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove

# set locale
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# python (python3)
RUN apt-get update \
  && apt-get install -yq python3 python3-pip python-is-python3 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove

# install python libs
RUN pip3 install --upgrade --break-system-packages \
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
  PyYAML

# install docker
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -yq docker-ce docker-ce-cli containerd.io docker-compose-plugin \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove

# install docker-compose (v2 via plugin symlink for backward compat)
RUN ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# install k8s tools
ARG K8S_VERSION=1.33
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list \
  && apt-get update \
  && apt-get install -yq kubelet kubeadm kubectl \
  && apt-mark hold kubelet kubeadm kubectl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove

# install consul nomad packer
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list \
  && apt-get update \
  && apt-get install -yq consul nomad packer \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get autoremove

# install tfenv
RUN git clone https://github.com/tfutils/tfenv.git /usr/local/tfenv \
  && ln -s /usr/local/tfenv/bin/* /usr/local/bin \
  && tfenv install 0.12.31 \
  && tfenv install 0.14.11 \
  && tfenv install 1.5.7 \
  && tfenv install 1.9.8 \
  && tfenv install 1.10.5 \
  && tfenv install 1.11.2 \
  && tfenv use 1.11.2

# install ansible from pip3
RUN pip3 install --upgrade ansible --break-system-packages

# # install tkg
# COPY resources/tkg-linux-amd64-v1.1.3_vmware.1.gz /tmp
# RUN gunzip /tmp/tkg-linux-amd64-v1.1.3_vmware.1.gz \
#   && mv /tmp/tkg-linux-amd64-v1.1.3_vmware.1 /usr/local/bin/tkg \
#   && chmod +x /usr/local/bin/tkg

# install aws cli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
  && unzip awscliv2.zip \
  && ./aws/install \
  && rm -rf ./aws awscliv2.zip

# Install AWS Session Manager plugin
RUN curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
        -o session-manager-plugin.deb
RUN dpkg -i session-manager-plugin.deb \
  && rm -rf session-manager-plugin.deb

# create entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# setup vim preferences for root
RUN echo "syntax on\nset number" > /root/.vimrc

# setup user
RUN groupadd -r ${LOCAL_USER} \
  && useradd --no-log-init -m -s /bin/zsh \
    -g ${LOCAL_USER} \
    -G audio,video \
    ${LOCAL_USER}
RUN mkdir -p /home/${LOCAL_USER} \
  && mkdir -p /home/${LOCAL_USER}/Downloads \
  && chown -R ${LOCAL_USER}:${LOCAL_USER} /home/${LOCAL_USER}

# setup local user password
RUN echo ${LOCAL_USER}:${LOCAL_USER} | chpasswd

# assign user to sudo
RUN adduser ${LOCAL_USER} sudo
RUN echo "${LOCAL_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# permit user to run docker
RUN usermod -aG docker ${LOCAL_USER}

# switch to local user
USER ${LOCAL_USER}
WORKDIR /home/${LOCAL_USER}

# setup vim preferences for user
RUN echo "syntax on\nset number" > /home/${LOCAL_USER}/.vimrc

# install ohmyzsh
RUN wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O - | zsh || true

# update ohmyzsh config
RUN sed -i 's/^ZSH_THEME=.*/ZSH_THEME=\"bira\"/g' /home/${LOCAL_USER}/.zshrc
RUN sed -i 's/^plugins=.*/plugins=\(git python ansible terraform\)/g' /home/${LOCAL_USER}/.zshrc

# install terraform autocomplete
RUN terraform -install-autocomplete

# install ansible plugins (required for ansible 2.10 and newer)
RUN /usr/local/bin/ansible-galaxy collection install \
  community.aws \
  community.azure \
  community.crypto \
  community.general \
  community.kubernetes \
  community.network \
  community.windows \
  amazon.aws

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "zsh" ]
