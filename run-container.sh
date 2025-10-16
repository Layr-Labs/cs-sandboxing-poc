#!/bin/bash

set -e  # Exit on any error

# Check required environment variable
if [ -z "$IMAGE" ]; then
    echo "ERROR: IMAGE environment variable is required" >&2
    exit 1
fi

echo "========================================="
echo "Starting container runtime setup"
echo "Image: $IMAGE"
echo "========================================="

# Configure cgroup delegation
echo "Setting up cgroup delegation..."
if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init.scope
    echo $$ > /sys/fs/cgroup/init.scope/cgroup.procs || {
        echo "ERROR: Failed to move process into cgroup" >&2
        exit 1
    }
    echo "+cpu +cpuset +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control || {
        echo "ERROR: Failed to enable cgroup controllers" >&2
        exit 1
    }
    echo "Cgroup delegation configured successfully"
else
    echo "WARNING: /sys/fs/cgroup/cgroup.subtree_control not found, skipping cgroup setup" >&2
fi

# Create runsc wrapper (keeping --host for platform mode)
echo "Creating runsc wrapper..."
cat > /usr/local/bin/runsc-host <<'EOF'
#!/bin/sh
exec /usr/local/bin/runsc "$@"
EOF
chmod +x /usr/local/bin/runsc-host
echo "Runsc wrapper created"

# Configure containerd with native snapshotter
echo "Configuring containerd..."
cat > /etc/containerd/config.toml <<EOF
version = 2

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "native"
  default_runtime_name = "runsc"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
  snapshotter = "native"
EOF
echo "Containerd configured with native snapshotter"

# Start containerd
echo "Starting containerd..."
containerd &
CONTAINERD_PID=$!
sleep 3

# Check if containerd started successfully
if ! kill -0 $CONTAINERD_PID 2>/dev/null; then
    echo "ERROR: containerd failed to start" >&2
    exit 1
fi
echo "Containerd started successfully (PID: $CONTAINERD_PID)"

# Pull the workload image
echo "Pulling image: $IMAGE"
if ! nerdctl --snapshotter=native pull "$IMAGE"; then
    echo "ERROR: Failed to pull image $IMAGE" >&2
    exit 1
fi
echo "Image pulled successfully"

# Detect exposed ports from the image using nerdctl inspect
echo "Detecting exposed ports from image..."
EXPOSED_PORTS=$(nerdctl --snapshotter=native image inspect "$IMAGE" | jq -r '.[0].Config.ExposedPorts // {} | keys[]' 2>/dev/null | sed 's/\/tcp$//' | sed 's/\/udp$//' | tr '\n' ' ')

# Trim whitespace
EXPOSED_PORTS=$(echo "$EXPOSED_PORTS" | xargs)

if [ -z "$EXPOSED_PORTS" ]; then
    echo "No exposed ports detected in image. Continuing without configuring iptables port restrictions."
    PORT_ARGS=""
else
    echo "Detected ports: $EXPOSED_PORTS"

    # Configure iptables to expose only detected ports
    echo "Configuring iptables to expose detected ports..."
    iptables -F INPUT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Build port mapping arguments and configure iptables
    PORT_ARGS=""
    for PORT in $EXPOSED_PORTS; do
        echo "  Allowing and mapping port $PORT"
        iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
        PORT_ARGS="$PORT_ARGS -p $PORT:$PORT"
    done

    iptables -A INPUT -j DROP
    echo "Iptables and port mapping configured successfully"
fi

# Run the container
CONTAINER_NAME="workload-$(date +%s)"
LOG_FILE="/tmp/${CONTAINER_NAME}.log"
echo "Starting container: $CONTAINER_NAME"
echo "Logs will be written to: $LOG_FILE"

# Start the container in the background and redirect output to log file (without --net=host)
nerdctl --snapshotter=native run $PORT_ARGS --runtime=runsc-host --name="$CONTAINER_NAME" "$IMAGE" > "$LOG_FILE" 2>&1 &
CONTAINER_PID=$!

# Wait a moment for container to start
sleep 2

# Check if container process is still running
if ! kill -0 $CONTAINER_PID 2>/dev/null; then
    echo "ERROR: Container failed to start" >&2
    cat "$LOG_FILE" >&2
    exit 1
fi

echo "Container started successfully (PID: $CONTAINER_PID)"
echo "========================================="
echo "Container is running. Monitoring logs..."
echo "========================================="

# Monitor container logs every 5 seconds
LAST_LINE=0
while true; do
    # Check if container is still running
    if ! kill -0 $CONTAINER_PID 2>/dev/null; then
        echo ""
        echo "ERROR: Container process exited" >&2
        tail -20 "$LOG_FILE" >&2
        exit 1
    fi

    # Print new log lines
    if [ -f "$LOG_FILE" ]; then
        CURRENT_LINES=$(wc -l < "$LOG_FILE")
        if [ "$CURRENT_LINES" -gt "$LAST_LINE" ]; then
            echo ""
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] New logs:"
            tail -n +$((LAST_LINE + 1)) "$LOG_FILE"
            LAST_LINE=$CURRENT_LINES
        fi
    fi

    sleep 5
done
