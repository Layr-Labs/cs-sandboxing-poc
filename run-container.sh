#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-}"
if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE environment variable required"
  exit 1
fi

# Make sure containerd dirs exist
mkdir -p /var/lib/containerd /run/containerd /etc/containerd

# Setup cgroup delegation (required for containerd to enforce resource limits)
if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
  mkdir -p /sys/fs/cgroup/init.scope
  echo $$ > /sys/fs/cgroup/init.scope/cgroup.procs || {
    echo "ERROR: Failed to move process into cgroup" >&2
    exit 1
  }
  echo "+cpu +cpuset +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control || {
    echo "WARNING: Could not enable all cgroup controllers" >&2
  }
fi

# containerd config (native snapshotter for gVisor)
cat >/etc/containerd/config.toml <<'EOF'
version = 2
[plugins."io.containerd.snapshotter.v1.native"]

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "native"
  default_runtime_name = "runsc"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
  snapshotter = "native"
EOF

echo "Starting containerd..."
containerd --log-level debug >/var/log/containerd.log 2>&1 &
CONTAINERD_PID=$!
echo "containerd started (PID: $CONTAINERD_PID)"

echo "Waiting for containerd..."
for i in {1..30}; do
  if ctr version >/dev/null 2>&1; then
    echo "containerd is ready!"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "ERROR: containerd failed to start"
    echo "=== containerd logs ==="
    cat /var/log/containerd.log
    exit 1
  fi
  sleep 1
done

# Create nerdctl-managed bridge network (no portmap, just bridge + firewall)
echo "Creating network..."
nerdctl network create \
  --driver bridge \
  --subnet 10.88.0.0/16 \
  --gateway 10.88.0.1 \
  workload-net || echo "Network already exists or failed to create"

echo "Running image $IMAGE with gVisor..."
CONTAINER_ID=$(nerdctl run -d \
  --snapshotter=native \
  --runtime=runsc \
  --network=workload-net \
  -e MY_VAR=foo \
  "${IMAGE}")

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
nerdctl logs "$CONTAINER_ID" 

# infinite loop
while true; do
  sleep 2
done

