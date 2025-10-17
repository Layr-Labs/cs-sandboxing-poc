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

echo "Reading ip forwarding status..."
cat /proc/sys/net/ipv4/ip_forward

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

# Create nerdctl-managed bridge network (no portmap, just bridge + firewall)
echo "Creating network..."
nerdctl network create \
  --driver bridge \
  --subnet 10.88.0.0/16 \
  --gateway 10.88.0.1 \
  workload-net

echo "Running image $IMAGE with gVisor..."
CONTAINER_ID=$(nerdctl run -d \
  --snapshotter=native \
  --runtime=runsc \
  --network=workload-net \
  "$IMAGE")

echo "Container started (ID: ${CONTAINER_ID:0:12})"

# Get container IP from CNI state files
echo "Getting container IP address..."
CONTAINER_IP=$(ls -t /var/lib/cni/networks/workload-net/ 2>/dev/null | head -1)

if [ -z "$CONTAINER_IP" ] || ! echo "$CONTAINER_IP" | grep -qE '^10\.88\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: Could not get container IP address from CNI"
  echo "=== CNI state files ==="
  ls -la /var/lib/cni/networks/workload-net/ 2>/dev/null || echo "No CNI state files found"
  nerdctl stop "$CONTAINER_ID" >/dev/null 2>&1
  nerdctl rm "$CONTAINER_ID" >/dev/null 2>&1
  exit 1
fi
echo "Container IP: $CONTAINER_IP"

# Get exposed ports from the image
echo "Setting up port forwarding..."
EXPOSED_PORTS=$(nerdctl image inspect "$IMAGE" 2>/dev/null | jq -r '.[0].Config.ExposedPorts | keys[]' | cut -d'/' -f1 2>/dev/null || echo "")

if [ -z "$EXPOSED_PORTS" ]; then
  echo "WARNING: No exposed ports found"
else
  # Forward incoming traffic to container
  for PORT in $EXPOSED_PORTS; do
    echo "Forwarding 0.0.0.0:$PORT -> $CONTAINER_IP:$PORT"
    iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $CONTAINER_IP:$PORT
    iptables -A FORWARD -d $CONTAINER_IP -p tcp --dport $PORT -j ACCEPT
  done

  # Enable masquerading for container outbound traffic
  iptables -t nat -A POSTROUTING -s 10.88.0.0/16 -j MASQUERADE

  echo "Port forwarding configured"
fi

echo "Tailing container logs..."
nerdctl logs -f "$CONTAINER_ID"
