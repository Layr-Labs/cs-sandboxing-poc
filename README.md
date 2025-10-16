# GCP Confidential Space Sandbox

This project runs a sandboxed workload container using gVisor inside a GCP Confidential Space instance.

## Quick Start

```sh
# Build the test workload image
./test-image/build-sandbox-tester.sh

# Build the sandbox container
./cloud build

# Setup firewall rule to allow health checks (one-time setup)
./cloud setup-firewall

# Create the GCP instance
./cloud create

# Get the instance IP and health check endpoints
./cloud ip

# View logs
./cloud logs

# When done, delete the instance
./cloud delete

# Cleanup firewall rule (if needed)
./cloud delete-firewall
```

## Health Check API

The workload exposes an HTTP API on port 8080:

- **GET /health** - Returns `{"status":"healthy"}` when the container is running

After creating an instance, use `./cloud ip` to get the external IP address:
- `http://<EXTERNAL_IP>:8080/health`

Diagnostic results are printed to the container logs (view with `./cloud logs`).

## Architecture

The sandbox container:
1. Runs containerd with gVisor (runsc) runtime
2. Pulls and executes the workload image inside the gVisor sandbox
3. The workload performs diagnostics and exposes HTTP endpoints
4. All network traffic is isolated within the sandbox

## Firewall Configuration

The instance is created with the `allow-health-check` network tag. The firewall rule allows TCP traffic on port 8080 from anywhere (0.0.0.0/0) to instances with this tag.