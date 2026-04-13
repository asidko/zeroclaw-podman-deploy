# ZeroClaw Podman Deploy

[![lint](https://github.com/asidko/zeroclaw-podman-deploy/actions/workflows/lint.yml/badge.svg)](https://github.com/asidko/zeroclaw-podman-deploy/actions/workflows/lint.yml)

[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) is an open-source AI agent runtime. This repo deploys it with one script — a production-ready daemon running in an isolated Podman container with auto-restart, persistent storage, and zero root required.

## 📋 Requirements

- **OS**: Linux (Debian/Ubuntu, Fedora/RHEL, Arch). WSL works.
- **Podman**: v4.0+ (rootless mode)
- **Disk**: ~2 GB for the container image

## 🚀 Quick Start

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

**3. On first start, ZeroClaw is installed from the official repository**

Inside the container, the deploy script uses this setup flow:

```sh
rm -rf /tmp/zeroclaw-install
git clone --depth=1 https://github.com/zeroclaw-labs/zeroclaw.git /tmp/zeroclaw-install
cd /tmp/zeroclaw-install
./install.sh --skip-onboard
rm -rf /tmp/zeroclaw-install
```

Then run onboarding:

```sh
./run.sh shell                                # ← enter the container
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

The daemon starts automatically after onboarding. On subsequent boots, it starts on its own. SSH is also exposed on host port `2222` by default, so you can connect and forward ports through the container when needed.

## 🛠 Commands

```
./run.sh start          Start container (creates on first run, resumes if stopped)
./run.sh stop           Stop container (preserves state)
./run.sh restart        Stop + start
./run.sh status         Check if container is running
./run.sh shell          Alias for: podman exec -it -u user zeroclaw /bin/bash
./run.sh update         Reinstall zeroclaw from a fresh official git checkout
./run.sh upgrade        Fresh shallow-clone upgrade from the official git repo
./run.sh version        Show installed zeroclaw version
./run.sh backup         Export container + data to timestamped .tar.gz
./run.sh restore <file> Restore from backup archive
./run.sh destroy        Remove container (data in .data/ is kept)
./run.sh rebuild        Destroy + rebuild image from scratch
./run.sh setup          Enable auto-restart after host reboot
```

## 🔐 SSH Access

The container runs an SSH server and exposes it on host loopback port `2222` by default:

```sh
ssh user@127.0.0.1 -p 2222
```

Default password inside the container:

```text
zeroclaw
```

Example port forwarding through the SSH connection:

```sh
ssh -N -L 3000:127.0.0.1:3000 user@127.0.0.1 -p 2222
```

You can then reach the forwarded service on your host at `127.0.0.1:3000`.

## 📝 Logs

Zeroclaw logs are available in `.data/zeroclaw-user-home/.zeroclaw/` on the host (bind-mounted from the container):

```sh
# audit log
podman unshare cat .data/zeroclaw-user-home/.zeroclaw/audit.log

# or check daemon output directly
podman logs zeroclaw
podman logs -f --tail 50 zeroclaw   # follow last 50 lines
```

## ⚙️ How It Works

- `run.sh` manages everything, `Containerfile` defines the image
- Your data lives in `.data/zeroclaw-user-home/` and survives restarts, destroys, and rebuilds
- If zeroclaw crashes, it auto-restarts. If the host reboots, the container auto-starts
- SSH runs inside the container on port `2222` for shell access and tunneling
- Runs without root via Podman rootless mode

## 🔓 Autonomy

Since zeroclaw runs inside an isolated container, you can safely grant it full permissions. Replace the entire `[autonomy]` section in `~/.zeroclaw/config.toml` inside the container with:

```toml
[autonomy]
level = "full"
workspace_only = false
allowed_commands = ["*"]
file_operations = "auto"
shell_commands = "auto"
web_search = "auto"
browser_automation = "auto"


[security.sandbox]
backend = "none"
```

Add the sudo wrapper rule to the agent instructions:

```sh
echo '**sudo → user_sudo.sh** — never use `sudo`. Always use `/usr/local/bin/user_sudo.sh` instead. Example: `user_sudo.sh apt install jq`.' >> ~/.zeroclaw/workspace/AGENTS.md
```

Then restart: `./run.sh restart`

## 💬 Messengers

Telegram, Discord, Slack, and other channels can be configured with:

```sh
podman exec -it -u user zeroclaw zeroclaw onboard --channels-only
```

## 💾 Backup & Restore

```sh
./run.sh backup
# creates zeroclaw_backup_20260314_120000.tar.gz

./run.sh restore zeroclaw_backup_20260314_120000.tar.gz
# existing container/data renamed with _old_ suffix, not deleted
```

Backups include the full container filesystem and user data, preserving any custom packages or modifications made inside the container.

The `update` command uses the official repository install flow inside the container:

```sh
rm -rf /tmp/zeroclaw-install
git clone --depth=1 https://github.com/zeroclaw-labs/zeroclaw.git /tmp/zeroclaw-install
cd /tmp/zeroclaw-install
./install.sh --skip-onboard
rm -rf /tmp/zeroclaw-install
```

The `upgrade` command also uses a fresh shallow clone in `/tmp` to avoid stale checkout state:

```sh
rm -rf /tmp/zeroclaw-install
git clone --depth=1 https://github.com/zeroclaw-labs/zeroclaw.git /tmp/zeroclaw-install
cd /tmp/zeroclaw-install
./install.sh --skip-onboard
rm -rf /tmp/zeroclaw-install
```

## 🧰 Pre-installed Tools

Python 3, Node.js 22, git, uv, gh, ripgrep, fd, fzf, jq, yq, tmux, sqlite3, build-essential, OpenSSH server, and more. Full list in `Containerfile`.
