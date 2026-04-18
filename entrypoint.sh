#!/bin/sh

BACKOFF=1
MAX_BACKOFF=60
HEALTHY_THRESHOLD=60
CHILD_PID=

start_sshd() {
    mkdir -p /run/sshd
    ssh-keygen -A >/dev/null 2>&1
    /usr/sbin/sshd
}

cleanup() {
    signum=$1
    [ -n "$CHILD_PID" ] && kill "$CHILD_PID" 2>/dev/null
    [ -n "$CHILD_PID" ] && wait "$CHILD_PID" 2>/dev/null
    exit $((128 + signum))
}
trap 'cleanup 15' TERM
trap 'cleanup 2'  INT
trap 'cleanup 1'  HUP
trap 'cleanup 3'  QUIT

start_sshd
mkdir -p /home/user/.zeroclaw

while true; do
    pgrep -x sshd >/dev/null 2>&1 || start_sshd
    START=$(date +%s)
    su - user -c "export SHELL=/bin/bash; zeroclaw daemon" &
    CHILD_PID=$!
    wait "$CHILD_PID"
    EXIT_CODE=$?
    CHILD_PID=
    ELAPSED=$(( $(date +%s) - START ))
    if [ "$ELAPSED" -ge "$HEALTHY_THRESHOLD" ]; then
        BACKOFF=1
    fi
    echo "[$(date)] zeroclaw daemon exited ($EXIT_CODE) after ${ELAPSED}s. Restarting in ${BACKOFF}s..." >&2
    sleep "$BACKOFF" &
    wait $!
    BACKOFF=$((BACKOFF * 2))
    [ "$BACKOFF" -gt "$MAX_BACKOFF" ] && BACKOFF=$MAX_BACKOFF
done
