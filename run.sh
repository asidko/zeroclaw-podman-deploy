#!/usr/bin/env bash
#
# ZeroClaw Podman Deploy
# Runs an isolated Ubuntu 24.04 LTS container via Podman rootless.
# The entrypoint loops `zeroclaw daemon` with exponential backoff.
# Network-isolated: slirp4netns with host loopback disabled.
#
# Host prerequisites:
#   Ubuntu/Debian:  sudo apt install -y podman
#   Fedora/RHEL:    sudo dnf install -y podman
#   Run './run.sh setup' once to enable container auto-restart after host reboot.
#
# Usage:
#   ./run.sh start          Start container (creates on first run, resumes if stopped)
#   ./run.sh stop           Stop container (preserves state and installed packages)
#   ./run.sh restart        Stop + start
#   ./run.sh status         Check if container is running
#   ./run.sh shell          Open interactive shell inside container
#   ./run.sh destroy        Remove container entirely (data in .data/ is kept)
#   ./run.sh rebuild        Destroy container + rebuild image from scratch
#   ./run.sh update         Update zeroclaw to latest version inside running container
#   ./run.sh version        Show installed zeroclaw version
#   ./run.sh backup         Export container + data into a timestamped .tar.gz
#   ./run.sh restore <file> Restore container + data from a backup archive
#   ./run.sh setup          Enable host-level auto-restart prerequisites (linger + podman-restart)
#
set -euo pipefail

# ── Help (before preflight so it works without podman) ────────────────────
case "${1:-}" in -h|--help|help) head -26 "$0" | tail -16; exit 0 ;; esac

# ── Preflight ─────────────────────────────────────────────────────────────
command -v podman >/dev/null 2>&1 || { echo "Error: podman is not installed. Run: sudo apt install -y podman"; exit 1; }
if ! grep -q "^$(whoami):" /etc/subuid 2>/dev/null; then
    echo "Error: rootless podman requires subuid/subgid entries for $(whoami)."
    echo "Fix:   sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(whoami) && podman system migrate"
    exit 1
fi

# ── Config ──────────────────────────────────────────────────────────────────
DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="zeroclaw"
IMAGE_NAME="zeroclaw-ubuntu"
DATA_DIR="$DIR/.data"
VM_USER="user"
GATEWAY_PORT="${GATEWAY_PORT:-}"

# ── Image Management ───────────────────────────────────────────────────────
image_exists() {
    podman image exists "$IMAGE_NAME" 2>/dev/null
}

build_image() {
    if image_exists; then
        echo "Image '$IMAGE_NAME' already exists. Use './run.sh rebuild' to force rebuild."
        return 0
    fi
    echo "Building image (this takes a few minutes on first run)..."
    podman build -t "$IMAGE_NAME" -f "$DIR/Containerfile" "$DIR"
}

rebuild_image() {
    destroy_container
    podman rmi -f "$IMAGE_NAME" 2>/dev/null || true
    echo "Building image from scratch..."
    podman build --no-cache -t "$IMAGE_NAME" -f "$DIR/Containerfile" "$DIR"
}

# ── Container Exec ─────────────────────────────────────────────────────────
vm_exec() {
    podman exec -u "$VM_USER" "$CONTAINER_NAME" "$@"
}

wait_for_ready() {
    echo "Waiting for container..."
    for _ in $(seq 1 15); do
        podman exec "$CONTAINER_NAME" true 2>/dev/null && echo "Container is up." && return 0
        sleep 1
    done
    echo "Warning: container not ready after 15 seconds."
    return 1
}

# ── Home Directory Init ─────────────────────────────────────────────────────
init_home_dir() {
    podman exec "$CONTAINER_NAME" chown -R "$VM_USER:$VM_USER" "/home/$VM_USER"
    if ! vm_exec test -f "/home/$VM_USER/.bashrc"; then
        echo "Initializing home directory..."
        vm_exec sh -c "cp /etc/skel/.bashrc /etc/skel/.profile /etc/skel/.bash_logout ~ 2>/dev/null || true"
    fi
    if ! vm_exec grep -q '.local/bin' "/home/$VM_USER/.bashrc" 2>/dev/null; then
        vm_exec sh -c 'echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc'
    fi
    if ! vm_exec test -x "/home/$VM_USER/.local/bin/zeroclaw"; then
        install_zeroclaw
    fi
}

install_zeroclaw() {
    echo "Installing zeroclaw..."
    vm_exec sh -c '
        set -e
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  ARCH="x86_64-unknown-linux-gnu" ;;
            aarch64) ARCH="aarch64-unknown-linux-gnu" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        mkdir -p ~/.local/bin
        TMP=$(mktemp -d)
        curl -fsSL "https://github.com/zeroclaw-labs/zeroclaw/releases/latest/download/zeroclaw-${ARCH}.tar.gz" -o "$TMP/zeroclaw.tar.gz"
        tar xzf "$TMP/zeroclaw.tar.gz" -C "$TMP"
        find "$TMP" -name zeroclaw -type f -exec cp {} ~/.local/bin/zeroclaw \;
        chmod +x ~/.local/bin/zeroclaw
        rm -rf "$TMP"
        echo "Installed: $(~/.local/bin/zeroclaw --version 2>/dev/null || echo "ok")"
    '
}

# ── Lifecycle ───────────────────────────────────────────────────────────────
is_running() {
    podman container exists "$CONTAINER_NAME" 2>/dev/null \
        && [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]
}

container_exists() {
    podman container exists "$CONTAINER_NAME" 2>/dev/null
}

create_container() {
    local image="$1"
    local run_args=(
        -d
        --name "$CONTAINER_NAME"
        --restart=always
        --init
        --network=slirp4netns:allow_host_loopback=false
        -v "$DATA_DIR/home:/home/$VM_USER:Z"
        -v "$DIR/entrypoint.sh:/usr/local/bin/entrypoint.sh:Z,ro"
        --log-opt max-size=10m
    )
    if [ -n "$GATEWAY_PORT" ]; then
        run_args+=(-p "${GATEWAY_PORT}:${GATEWAY_PORT}")
    fi
    podman run "${run_args[@]}" "$image" /usr/local/bin/entrypoint.sh
}

start_container() {
    if is_running; then
        echo "Container '$CONTAINER_NAME' already running."
        return 0
    fi

    if container_exists; then
        echo "Resuming stopped container..."
        podman start "$CONTAINER_NAME"
        wait_for_ready
        return 0
    fi

    build_image
    mkdir -p "$DATA_DIR/home"
    echo "Creating container..."
    create_container "$IMAGE_NAME"

    if wait_for_ready; then
        init_home_dir
    fi
}

stop_container() {
    if ! is_running; then
        echo "Container not running."
        return 0
    fi
    echo "Stopping container..."
    podman stop -t 10 "$CONTAINER_NAME"
    echo "Container stopped. State preserved — use 'start' to resume."
}

destroy_container() {
    stop_container 2>/dev/null || true
    if container_exists; then
        echo "Removing container..."
        podman rm "$CONTAINER_NAME"
        echo "Container removed."
    fi
}

status_container() {
    if is_running; then
        echo "Container running."
        podman ps --filter "name=$CONTAINER_NAME" --format "table {{.ID}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "Container not running."
    fi
}

update_zeroclaw() {
    is_running || { echo "Container not running. Start it first."; return 1; }
    install_zeroclaw
    echo "Restarting container to apply update..."
    podman restart "$CONTAINER_NAME"
    wait_for_ready
}

show_version() {
    is_running || { echo "Container not running. Start it first."; return 1; }
    vm_exec sh -c 'PATH=~/.local/bin:$PATH zeroclaw --version 2>/dev/null || echo "unknown"'
}

backup_container() {
    container_exists || { echo "No container to backup."; return 1; }
    local ts tmp
    ts=$(date +%Y%m%d_%H%M%S)
    local out="$DIR/zeroclaw_backup_${ts}.tar.gz"
    tmp=$(mktemp -d)

    echo "Exporting container..."
    podman export "$CONTAINER_NAME" > "$tmp/container.tar"
    echo "Archiving data..."
    podman unshare tar cf "$tmp/data.tar" -C "$DATA_DIR" .
    tar czf "$out" -C "$tmp" container.tar data.tar
    rm -rf "$tmp"

    echo "Backup saved: $out ($(du -h "$out" | cut -f1))"
}

restore_container() {
    local archive="$1"
    [ -f "$archive" ] || { echo "File not found: $archive"; return 1; }
    local ts tmp
    ts=$(date +%Y%m%d_%H%M%S)
    tmp=$(mktemp -d)

    tar xzf "$archive" -C "$tmp"
    if [ ! -f "$tmp/container.tar" ] || [ ! -f "$tmp/data.tar" ]; then
        rm -rf "$tmp"
        echo "Invalid backup archive."
        return 1
    fi

    if container_exists; then
        stop_container 2>/dev/null || true
        podman rename "$CONTAINER_NAME" "${CONTAINER_NAME}_old_${ts}"
    fi
    [ -d "$DATA_DIR" ] && podman unshare mv "$DATA_DIR" "${DATA_DIR}_old_${ts}"

    mkdir -p "$DATA_DIR"
    podman unshare tar xf "$tmp/data.tar" -C "$DATA_DIR"

    local img="${IMAGE_NAME}:restored_${ts}"
    podman import "$tmp/container.tar" "$img"
    create_container "$img"
    rm -rf "$tmp"
    wait_for_ready
    echo "Restore complete. Old container/data saved with _old_${ts} suffix."
}

setup_host() {
    sudo loginctl enable-linger "$(whoami)"
    systemctl --user enable podman-restart.service
    echo "Verifying..."
    loginctl show-user "$(whoami)" | grep Linger
    systemctl --user is-enabled podman-restart.service
    echo "Host setup complete. Containers with --restart=always will auto-start after reboot."
}

# ── Entrypoint ──────────────────────────────────────────────────────────────
case "${1:-start}" in
    start)   start_container ;;
    stop)    stop_container ;;
    restart) stop_container; start_container ;;
    status)  status_container ;;
    shell)   podman exec -it -u "$VM_USER" "$CONTAINER_NAME" /bin/bash ;;
    destroy) destroy_container ;;
    rebuild) rebuild_image ;;
    update)  update_zeroclaw ;;
    version) show_version ;;
    backup)  backup_container ;;
    restore) shift; restore_container "${1:?Usage: $0 restore <backup_file>}" ;;
    setup)   setup_host ;;
    *)       echo "Usage: $0 {start|stop|restart|status|shell|destroy|rebuild|update|version|backup|restore|setup|help}"; exit 1 ;;
esac
