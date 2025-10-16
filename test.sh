#!/bin/sh
set -x

# Setup cgroup delegation for gVisor
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

# Create runsc wrapper with --network=host flag
cat > /usr/local/bin/runsc-host <<'EOF'
#!/bin/sh
exec /usr/local/bin/runsc --network=host "$@"
EOF
chmod +x /usr/local/bin/runsc-host

# Create containerd config with native snapshotter for gVisor compatibility
mkdir -p /etc/containerd
cat > /etc/containerd/config.toml <<EOF
version = 2

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "native"
  default_runtime_name = "runsc"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
  snapshotter = "native"
EOF

# Start containerd
containerd &
sleep 3

# Pull images
ctr image pull docker.io/hashicorp/http-echo:latest
ctr image pull docker.io/curlimages/curl:latest

# Start echo server with gVisor
echo "Starting echo server..."
ctr run -d --net-host --snapshotter native --runc-binary runsc-host \
    docker.io/hashicorp/http-echo:latest \
    echo-server \
    /http-echo -listen=0.0.0.0:8080 -text="Hello"

sleep 2

# Test from host script directly
echo ""
echo "========================================="
echo "Test 0: Direct curl from host script"
echo "========================================="
curl -v http://localhost:8080
echo ""

# Test local
echo "========================================="
echo "Test 1: Container-to-container (http://localhost:8080)"
echo "========================================="
ctr run --rm --net-host --snapshotter native --runc-binary runsc-host \
    docker.io/curlimages/curl:latest \
    test1 \
    curl -v http://localhost:8080
echo ""

# Test external
echo "========================================="
echo "Test 2: External connectivity (https://ifconfig.me)"
echo "========================================="
ctr run --rm --net-host --snapshotter native --runc-binary runsc-host \
    docker.io/curlimages/curl:latest \
    test2 \
    curl -v https://ifconfig.me
echo ""

printf "\nDone. Server on :8080\n"
tail -f /dev/null