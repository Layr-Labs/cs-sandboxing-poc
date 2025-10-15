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

echo "Running image $IMAGE with gVisor..."
nerdctl run --rm \
  --snapshotter=native \
  --runtime=runsc \
  -e MY_VAR=foo \
  "${IMAGE}"