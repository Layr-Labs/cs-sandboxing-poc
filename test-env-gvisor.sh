#!/bin/bash

echo "=== Environment & gVisor Test ==="
echo ""

echo "1. Checking IMAGE environment variable:"
if [ -z "$IMAGE" ]; then
    echo "   ✗ IMAGE not set"
else
    echo "   ✓ IMAGE = $IMAGE"
fi

echo ""
echo "2. All environment variables:"
env | sort

echo ""
echo "3. Checking if running in gVisor:"
echo "   Checking dmesg for gVisor indicators..."
if dmesg 2>/dev/null | grep -i "gvisor\|runsc" > /dev/null; then
    echo "   ✓ Found gVisor in dmesg"
else
    echo "   ✗ No gVisor indicators in dmesg"
fi

echo ""
echo "4. Container capabilities:"
if command -v capsh > /dev/null 2>&1; then
    capsh --print
else
    echo "   capsh not available, checking /proc/self/status:"
    grep Cap /proc/self/status || echo "   Unable to read capabilities"
fi

echo ""
echo "5. Cgroup namespace check:"
if [ -d "/sys/fs/cgroup" ]; then
    echo "   ✓ /sys/fs/cgroup exists"
    ls -la /sys/fs/cgroup/ | head -10
else
    echo "   ✗ /sys/fs/cgroup not found"
fi

echo ""
echo "=== Test Complete ==="
