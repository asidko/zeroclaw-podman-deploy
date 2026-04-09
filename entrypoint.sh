#!/bin/sh

BACKOFF=1
MAX_BACKOFF=60
HEALTHY_THRESHOLD=60
CHILD_PID=

cleanup() {
    [ -n "$CHILD_PID" ] && kill "$CHILD_PID" 2>/dev/null
    exit 0
}
trap cleanup TERM INT

while true; do
    START=$(date +%s)
    su - user -c "export PATH=/home/user/.local/bin:\$PATH; zeroclaw daemon" &
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
