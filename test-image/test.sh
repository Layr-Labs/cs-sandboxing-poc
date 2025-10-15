#!/bin/bash

echo "=== Environment & gVisor Test ==="
echo ""

echo "1. All environment variables:"
env | sort

echo ""
echo "2. Checking if running in gVisor:"
echo "   Checking dmesg for gVisor indicators..."
if dmesg 2>/dev/null | grep -i "gvisor\|runsc" > /dev/null; then
    echo "   ✓ Found gVisor in dmesg"
else
    echo "   ✗ No gVisor indicators in dmesg"
fi

echo ""
echo "3. Container capabilities:"
if command -v capsh > /dev/null 2>&1; then
    capsh --print
else
    echo "   capsh not available, checking /proc/self/status:"
    grep Cap /proc/self/status || echo "   Unable to read capabilities"
fi

echo ""
echo "4. Cgroup namespace check:"
if [ -d "/sys/fs/cgroup" ]; then
    echo "   ✓ /sys/fs/cgroup exists"
    ls -la /sys/fs/cgroup/ | head -10
else
    echo "   ✗ /sys/fs/cgroup not found"
fi

echo ""
echo "5. Network configuration:"
echo "   Network interfaces:"
ip addr show 2>/dev/null || ifconfig -a 2>/dev/null || echo "   Cannot list interfaces"

echo ""
echo "   Routing table:"
ip route show 2>/dev/null || route -n 2>/dev/null || echo "   Cannot show routes"

echo ""
echo "   DNS configuration:"
cat /etc/resolv.conf 2>/dev/null || echo "   Cannot read resolv.conf"

echo ""
echo "6. Testing TEE attestation service (should fail outside Confidential Space):"
TEE_SOCKET="/run/container_launcher/teeserver.sock"
if [ -S "$TEE_SOCKET" ]; then
    echo "   Found TEE socket at $TEE_SOCKET"
    echo "   Attempting to request attestation token..."
    RESPONSE=$(curl -s -w "\n%{http_code}" --unix-socket "$TEE_SOCKET" \
        -X POST http://localhost/v1/token \
        -H "Content-Type: application/json" \
        -d '{
            "audience": "test-audience",
            "token_type": "OIDC",
            "nonces": ["test-nonce-123456"]
        }' 2>&1 || echo "000")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "000" ] || [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "500" ]; then
        echo "   ✓ TEE service unavailable as expected (HTTP $HTTP_CODE)"
    else
        echo "   ! Unexpected response (HTTP $HTTP_CODE): $BODY"
    fi
else
    echo "   ✓ TEE socket not found (expected outside Confidential Space)"
fi

echo ""
echo "7. Testing public internet connectivity:"
echo "   Attempting to reach example.com..."
curl -s -m 5 --head https://example.com 
if curl -s -m 5 --head https://example.com > /dev/null 2>&1; then
    echo "   ✓ Public internet is accessible"
else
    echo "   ✗ Cannot reach public internet"
    
    echo ""
    echo "   Debugging connectivity issues:"
    echo "   - Testing DNS resolution..."
    if nslookup example.com >/dev/null 2>&1; then
        echo "     ✓ DNS resolution works"
    elif host example.com >/dev/null 2>&1; then
        echo "     ✓ DNS resolution works (via host)"
    else
        echo "     ✗ DNS resolution failed"
    fi
    
    echo "   - Testing connectivity to 8.8.8.8..."
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo "     ✓ Can ping 8.8.8.8"
    else
        echo "     ✗ Cannot ping 8.8.8.8"
    fi
    
    GATEWAY=$(ip route show 2>/dev/null | grep default | awk '{print $3}' | head -1)
    if [ -n "$GATEWAY" ]; then
        echo "   - Testing connectivity to gateway $GATEWAY..."
        if ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1; then
            echo "     ✓ Can ping gateway"
        else
            echo "     ✗ Cannot ping gateway"
        fi
    fi
fi

echo ""
echo "=== Test Complete ==="