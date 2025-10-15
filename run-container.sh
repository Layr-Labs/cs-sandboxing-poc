#!/bin/bash
set -euo pipefail

IMAGE="${IMAGE:-}"
if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE environment variable required"
  exit 1
fi

# Make sure containerd dirs exist
mkdir -p /var/lib/containerd /run/containerd /etc/containerd

# runsc wrapper
if [ ! -f /usr/local/bin/runsc-real ]; then
  echo "Creating runsc wrapper to ignore cgroups..."
  mv /usr/local/bin/runsc /usr/local/bin/runsc-real
  cat >/usr/local/bin/runsc <<'EOF'
#!/bin/sh
exec /usr/local/bin/runsc-real --ignore-cgroups "$@"
EOF
  chmod +x /usr/local/bin/runsc
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