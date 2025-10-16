package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
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
	err := checkGVisor()
	if err != nil {
		fmt.Println("✗ gVisor not detected", err)
	} else {
		fmt.Println("✓ gVisor detected")
	}

	// 3. Capabilities
	fmt.Println("\n3. Container capabilities:")
	fmt.Println(getCapabilities())

	// 4. TEE attestation service
	fmt.Println("\n6. Testing TEE attestation service (should fail outside Confidential Space):")
	err = checkTEESocketDoesNotExist()
	if err != nil {
		fmt.Println("✗ TEE socket found, unexpected:", err)
	} else {
		fmt.Println("✓ TEE socket not found")
	}

	// 5. Internet connectivity
	fmt.Println("\n7. Testing public internet connectivity:")
	err = checkInternet()
	if err != nil {
		fmt.Println("✗ Cannot reach public internet", err)
	} else {
		fmt.Println("✓ Public internet is accessible")
	}

	// 6. File I/O test
	fmt.Println("\n8. Checking file creation and deletion:")
	err = checkFileIO()
	if err != nil {
		fmt.Println("✗ File I/O checks failed:", err)
	} else {
		fmt.Println("✓ File I/O checks passed")
	}
}

func checkGVisor() error {
	out, err := runCommand("dmesg")
	if err != nil {
		return err
	}

	fmt.Println("dmesg output:", out)

	lower := strings.ToLower(out)
	if !strings.Contains(lower, "gvisor") && !strings.Contains(lower, "runsc") {
		return fmt.Errorf("dmesg output does not indicate gVisor")
	}
	return nil
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

func checkTEESocketDoesNotExist() error {
	_, err := os.Stat("/run/container_launcher/teeserver.sock")
	if os.IsNotExist(err) {
		return nil // Expected - socket doesn't exist
	}
	if err == nil {
		return fmt.Errorf("TEE socket exists but shouldn't")
	}
	return err
}

func checkInternet() error {
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest("GET", "https://ifconfig.me", nil)
	if err != nil {
		return err
	}

	// Set user agent to mimic curl so we get just the IP
	req.Header.Set("User-Agent", "curl/7.68.0")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 400 {
		return fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	// Print just the IP address
	fmt.Printf("External IP: %s\n", strings.TrimSpace(string(body)))

	return nil
}

func checkFileIO() error {
	// Create a temporary directory for testing
	testDir := "/tmp/fileio-test"
	err := os.MkdirAll(testDir, 0755)
	if err != nil {
		return fmt.Errorf("failed to create test directory: %w", err)
	}

	// Create 100 test files
	fileCount := 100
	fmt.Printf("Creating %d test files...\n", fileCount)
	for i := 0; i < fileCount; i++ {
		filename := fmt.Sprintf("%s/test-file-%d.txt", testDir, i)
		content := fmt.Sprintf("Test file %d - timestamp: %s", i, time.Now().Format(time.RFC3339))
		err := os.WriteFile(filename, []byte(content), 0644)
		if err != nil {
			return fmt.Errorf("failed to create file %s: %w", filename, err)
		}
	}
	fmt.Printf("Successfully created %d files\n", fileCount)

	// Verify files exist
	entries, err := os.ReadDir(testDir)
	if err != nil {
		return fmt.Errorf("failed to read test directory: %w", err)
	}
	if len(entries) != fileCount {
		return fmt.Errorf("expected %d files, found %d", fileCount, len(entries))
	}
	fmt.Printf("Verified %d files exist\n", len(entries))

	// Delete all test files
	fmt.Printf("Deleting %d test files...\n", fileCount)
	for i := 0; i < fileCount; i++ {
		filename := fmt.Sprintf("%s/test-file-%d.txt", testDir, i)
		err := os.Remove(filename)
		if err != nil {
			return fmt.Errorf("failed to delete file %s: %w", filename, err)
		}
	}
	fmt.Printf("Successfully deleted %d files\n", fileCount)

	// Remove the test directory
	err = os.Remove(testDir)
	if err != nil {
		return fmt.Errorf("failed to remove test directory: %w", err)
	}

	return nil
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
