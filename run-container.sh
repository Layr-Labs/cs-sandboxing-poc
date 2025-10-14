#!/bin/bash

set -e

IMAGE="${IMAGE:-}"

if [ -z "$IMAGE" ]; then
    echo "ERROR: IMAGE environment variable required"
    exit 1
fi

# Create docker data directory
mkdir -p /tmp/docker-data || echo "Warning: failed to create docker data dir"

# Start Docker daemon
echo "Starting Docker daemon..."
dockerd \
    --host=unix:///tmp/docker.sock \
    --data-root=/tmp/docker-data \
    --debug \
    --log-level=debug \
    --iptables=false \
    --ip-forward=false \
    --bridge=none \
    --storage-driver=vfs \
    > /var/log/dockerd.log 2>&1 &

DOCKERD_PID=$!
echo "Docker daemon started (PID: $DOCKERD_PID)"

# Wait for Docker daemon to be ready
echo "Waiting for Docker to start..."
for i in {1..240}; do  # 240 * 0.25s = 60s
    if [ -S "/tmp/docker.sock" ]; then
        echo "Docker socket is ready!"
        break
    fi
    if [ $i -eq 240 ]; then
        echo "ERROR: Docker daemon failed to start after 60 seconds"
        echo ""
        echo "=== Daemon logs ==="
        cat /var/log/dockerd.log
        exit 1
    fi
    sleep 0.25
done

# Run container with gVisor runtime
echo "Running image $IMAGE with gVisor..."

export DOCKER_HOST=unix:///tmp/docker.sock

docker run --rm \
    --privileged \
    --runtime=runsc \
    -e MY_VAR=foo \
    "$IMAGE"

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "Container exited with error: $EXIT_CODE"
    exit 1
fi

echo "Container exited successfully"
