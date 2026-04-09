FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# core tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git htop tmux vim nano jq unzip zip file sudo direnv \
    # build toolchain
    build-essential \
    # python
    python3 python3-pip python3-venv \
    # code search & navigation
    ripgrep fd-find tree fzf \
    # networking
    net-tools dnsutils iputils-ping netcat-openbsd openssl \
    openssh-client rsync \
    # databases
    sqlite3 \
    # process debugging
    lsof psmisc \
    # compression
    bzip2 xz-utils \
    # tls/auth
    ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# github cli
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# yq
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_linux_${ARCH}" \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# user setup
RUN useradd -m -s /bin/bash -G sudo user \
    && echo "user:zeroclaw" | chpasswd \
    && echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user

# uv (python package manager) - install system-wide since /home/user is a mounted volume
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
