# ZeroClaw Podman Deploy

[![lint](https://github.com/asidko/zeroclaw-podman-deploy/actions/workflows/lint.yml/badge.svg)](https://github.com/asidko/zeroclaw-podman-deploy/actions/workflows/lint.yml)

[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) is an open-source AI agent runtime. This repo deploys it with one script — a production-ready daemon running in an isolated Podman container with auto-restart, persistent storage, and zero root required.

## Requirements

- **OS**: Linux (Debian/Ubuntu, Fedora/RHEL, Arch). WSL works.
- **Podman**: v4.0+ (rootless mode)
- **Disk**: ~2 GB for the container image

## Quick Start

**1. Install Podman** (skip if already installed)

```sh
sudo apt install -y podman    # Debian/Ubuntu
sudo dnf install -y podman    # Fedora/RHEL
```

**2. Clone and start**

```sh
git clone https://github.com/asidko/zeroclaw-podman-deploy.git
cd zeroclaw-podman-deploy
./run.sh start    # ← builds image and starts container on first run
```

**3. Run the onboarding wizard** (configures provider, API keys, and workspace)

```sh
podman exec -it -u user zeroclaw /bin/bash   # ← enter the container
zeroclaw onboard                              # ← interactive wizard: configures provider, API keys, and workspace
exit                                          # ← back to host
```

**4. Enable auto-restart after reboot** (run once)

```sh
./run.sh setup    # ← enables systemd linger + podman-restart service
```

**5. Verify**

```sh
./run.sh status   # ← should show "Container running."
```

The daemon starts automatically after onboarding. On subsequent boots, it starts on its own.

## Commands

```
./run.sh start          Start container (creates on first run, resumes if stopped)
./run.sh stop           Stop container (preserves state)
./run.sh restart        Stop + start
./run.sh status         Check if container is running
./run.sh update         Update zeroclaw to latest version
./run.sh version        Show installed zeroclaw version
./run.sh backup         Export container + data to timestamped .tar.gz
./run.sh restore <file> Restore from backup archive
./run.sh destroy        Remove container (data in .data/ is kept)
./run.sh rebuild        Destroy + rebuild image from scratch
./run.sh setup          Enable auto-restart after host reboot
```

## Logs

Zeroclaw logs are available in `.data/home/.zeroclaw/` on the host (bind-mounted from the container):

```sh
# audit log
podman unshare cat .data/home/.zeroclaw/audit.log

# or check daemon output directly
podman logs zeroclaw
podman logs -f zeroclaw        # follow
podman logs --tail 50 zeroclaw # last 50 lines
```

## How It Works

- **Single script**: `run.sh` manages the full container lifecycle, `Containerfile` defines the image
- **Persistent home**: `/home/user` is mounted to `.data/home/` — survives stop/start and destroy/rebuild
- **Auto-restart**: `zeroclaw daemon` restarts with exponential backoff (1s to 60s, resets after healthy run); container restarts via `--restart=always`
- **Network isolated**: `slirp4netns` with host loopback disabled — container cannot reach host services
- **Rootless**: runs entirely without root via Podman user namespaces
- **Gateway port**: `42617` (default, inside container)

## Backup & Restore

```sh
./run.sh backup
# creates zeroclaw_backup_20260314_120000.tar.gz

./run.sh restore zeroclaw_backup_20260314_120000.tar.gz
# existing container/data renamed with _old_ suffix, not deleted
```

Backups include the full container filesystem and user data, preserving any custom packages or modifications made inside the container.

## Pre-installed Tools

Python 3, Node.js 22, git, uv, gh, ripgrep, fd, fzf, jq, yq, tmux, sqlite3, build-essential, and more. Full list in `Containerfile`.
