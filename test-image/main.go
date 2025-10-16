package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"
)

func main() {
	log.Println("=== Environment & gVisor Test ===")

	// Run all diagnostics
	runDiagnostics()

	// Start HTTP server
	http.HandleFunc("/health", healthHandler)

	log.Println("\nStarting HTTP server on :8080")
	log.Println("Endpoint: GET /health - Health check")

	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func runDiagnostics() {
	fmt.Printf("\nTimestamp: %s\n\n", time.Now().Format(time.RFC3339))

	// 1. Environment variables
	fmt.Println("1. All environment variables:")
	envVars := os.Environ()
	sort.Strings(envVars)
	for _, env := range envVars {
		fmt.Println(env)
	}

	// 2. Check for gVisor
	fmt.Println("\n2. Checking if running in gVisor:")
	if checkGVisor() {
		fmt.Println("✓ Found gVisor in dmesg")
	} else {
		fmt.Println("✗ No gVisor indicators in dmesg")
	}

	// 3. Capabilities
	fmt.Println("\n3. Container capabilities:")
	fmt.Println(getCapabilities())

	// 4. Cgroup check
	fmt.Println("\n4. Cgroup namespace check:")
	if _, err := os.Stat("/sys/fs/cgroup"); err == nil {
		fmt.Println("✓ /sys/fs/cgroup exists")
		if out, err := runCommand("ls", "-la", "/sys/fs/cgroup/"); err == nil {
			lines := strings.Split(out, "\n")
			if len(lines) > 10 {
				lines = lines[:10]
			}
			fmt.Println(strings.Join(lines, "\n"))
		}
	} else {
		fmt.Println("✗ /sys/fs/cgroup not found")
	}

	// 5. Network configuration
	fmt.Println("\n5. Network configuration:")
	fmt.Println("Network interfaces:")
	fmt.Println(getNetworkInterfaces())

	fmt.Println("\nRouting table:")
	fmt.Println(getRoutes())

	fmt.Println("\nDNS configuration:")
	fmt.Println(getDNS())

	// 6. TEE attestation service
	fmt.Println("\n6. Testing TEE attestation service (should fail outside Confidential Space):")
	if checkTEESocket() {
		fmt.Println("Found TEE socket (unexpected outside Confidential Space)")
	} else {
		fmt.Println("✓ TEE socket not found (expected outside Confidential Space)")
	}

	// 7. Internet connectivity
	fmt.Println("\n7. Testing public internet connectivity:")
	if checkInternet() {
		fmt.Println("✓ Public internet is accessible")
	} else {
		fmt.Println("✗ Cannot reach public internet")
		fmt.Print(debugConnectivity())
	}

	fmt.Println("\n=== Test Complete ===")
}

func checkGVisor() bool {
	out, err := runCommand("dmesg")
	if err != nil {
		return false
	}
	lower := strings.ToLower(out)
	return strings.Contains(lower, "gvisor") || strings.Contains(lower, "runsc")
}

func getCapabilities() string {
	// Try capsh first
	if out, err := runCommand("capsh", "--print"); err == nil {
		return out
	}

	// Fallback to /proc/self/status
	if data, err := os.ReadFile("/proc/self/status"); err == nil {
		lines := strings.Split(string(data), "\n")
		var caps []string
		for _, line := range lines {
			if strings.HasPrefix(line, "Cap") {
				caps = append(caps, line)
			}
		}
		if len(caps) > 0 {
			return strings.Join(caps, "\n")
		}
	}

	return "Unable to read capabilities"
}

func getNetworkInterfaces() string {
	// Try ip addr show
	if out, err := runCommand("ip", "addr", "show"); err == nil {
		return out
	}

	// Fallback to ifconfig
	if out, err := runCommand("ifconfig", "-a"); err == nil {
		return out
	}

	return "Cannot list interfaces"
}

func getRoutes() string {
	// Try ip route show
	if out, err := runCommand("ip", "route", "show"); err == nil {
		return out
	}

	// Fallback to route
	if out, err := runCommand("route", "-n"); err == nil {
		return out
	}

	return "Cannot show routes"
}

func getDNS() string {
	if data, err := os.ReadFile("/etc/resolv.conf"); err == nil {
		return string(data)
	}
	return "Cannot read resolv.conf"
}

func checkTEESocket() bool {
	teeSocket := "/run/container_launcher/teeserver.sock"
	if info, err := os.Stat(teeSocket); err == nil && info.Mode()&os.ModeSocket != 0 {
		return true
	}
	return false
}

func checkInternet() bool {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Head("https://example.com")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 400
}

func debugConnectivity() string {
	var debug strings.Builder
	fmt.Fprintln(&debug, "\nDebugging connectivity issues:")

	// Test DNS
	fmt.Fprintln(&debug, "Testing DNS resolution...")
	if _, err := runCommand("nslookup", "example.com"); err == nil {
		fmt.Fprintln(&debug, "✓ DNS resolution works")
	} else if _, err := runCommand("host", "example.com"); err == nil {
		fmt.Fprintln(&debug, "✓ DNS resolution works (via host)")
	} else {
		fmt.Fprintln(&debug, "✗ DNS resolution failed")
	}

	// Test ping to 8.8.8.8
	fmt.Fprintln(&debug, "Testing connectivity to 8.8.8.8...")
	if _, err := runCommand("ping", "-c", "1", "-W", "2", "8.8.8.8"); err == nil {
		fmt.Fprintln(&debug, "✓ Can ping 8.8.8.8")
	} else {
		fmt.Fprintln(&debug, "✗ Cannot ping 8.8.8.8")
	}

	// Test gateway
	if gateway := getGateway(); gateway != "" {
		fmt.Fprintf(&debug, "Testing connectivity to gateway %s...\n", gateway)
		if _, err := runCommand("ping", "-c", "1", "-W", "2", gateway); err == nil {
			fmt.Fprintln(&debug, "✓ Can ping gateway")
		} else {
			fmt.Fprintln(&debug, "✗ Cannot ping gateway")
		}
	}

	return debug.String()
}

func getGateway() string {
	out, err := runCommand("ip", "route", "show")
	if err != nil {
		return ""
	}

	lines := strings.Split(out, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "default") {
			fields := strings.Fields(line)
			if len(fields) >= 3 {
				return fields[2]
			}
		}
	}
	return ""
}

func runCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return "", err
	}

	return stdout.String(), nil
}
