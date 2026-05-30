#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Kill existing gateway process
pid=$(pgrep -f "AxionCLI gateway" || true)
if [ -n "$pid" ]; then
    echo "[axion] Killing existing gateway (pid $pid)"
    kill $pid 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi
fi

# Ensure log directory
mkdir -p ~/.axion/logs

# Build
echo "[axion] Building..."
swift build -q

# Start in background with log
logfile=~/.axion/logs/gateway-$(date +%Y%m%d-%H%M%S).log
echo "[axion] Starting gateway on 127.0.0.1:4242"
echo "[axion] Log: $logfile"

nohup .build/arm64-apple-macosx/debug/AxionCLI gateway start \
    --host 127.0.0.1 --port 4242 \
    >> "$logfile" 2>&1 &
echo "[axion] Gateway started (pid $!)"
