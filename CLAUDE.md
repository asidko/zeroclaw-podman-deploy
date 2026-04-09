# ZeroClaw Podman Deploy

## What this is
Self-hosted deployment of [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) (Rust binary, AI agent gateway) in a rootless Podman container on Ubuntu 24.04 LTS. Modeled after openclaw-podman-deploy (sibling repo at `../openclaw-podman-deploy`).

## Architecture
- `run.sh` — lifecycle manager (start/stop/rebuild/backup/restore/update)
- `entrypoint.sh` — PID supervisor inside the container, runs `zeroclaw daemon` via `su - user` with exponential backoff. Uses background `wait` pattern so SIGTERM trap fires immediately
- `Containerfile` — static, committed (not generated). Ubuntu 24.04 + dev tools + Node.js 22
- `.data/home/` — bind-mounted persistent volume for `/home/user` inside container. Contains zeroclaw binary at `.local/bin/zeroclaw` and config at `.zeroclaw/config.toml`

## Key decisions
- ZeroClaw is a **Rust binary** installed from GitHub releases, NOT npm. The `zeroclaw` npm package is an unrelated TS SDK from clawrun.sh
- Binary lives on the bind-mount (`~/.local/bin/`) so it survives `destroy`+`start`. Image rebuild doesn't lose it
- `zeroclaw daemon` is the full runtime (gateway + channels + cron). Gateway alone is `zeroclaw gateway` (port 42617)
- `zeroclaw onboard` is the interactive setup wizard (provider, API keys, workspace)
- Container networking: `slirp4netns:allow_host_loopback=false`. No ports published by default. `GATEWAY_PORT` env var adds `-p` flag
- `.data/` files are owned by podman user namespace — use `podman unshare` for host-side access
- `--log-opt max-size=10m` prevents unbounded log growth

## Agents
- Use `.claude/agents/zeroclaw-ops.md` for any zeroclaw operations, configuration, diagnostics, provider setup, channel management, or runtime troubleshooting

## Operations context
- Zeroclaw runs inside a podman container named `zeroclaw` on the user's machine
- For deployment/lifecycle tasks (start, stop, rebuild, backup): use `run.sh`
- For zeroclaw runtime tasks (config, providers, channels, onboard, diagnostics): `podman exec -it -u user zeroclaw /bin/bash` then run zeroclaw CLI commands inside the container
- Config file inside container: `~/.zeroclaw/config.toml`. From host: `.data/home/.zeroclaw/config.toml` (requires `podman unshare` for access)

## Shell conventions
- All shell scripts must pass `shellcheck` at warning severity (CI enforced)
- `entrypoint.sh` is POSIX `sh`, `run.sh` is `bash`
