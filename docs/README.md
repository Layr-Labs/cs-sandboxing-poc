# Confidential Space Sandboxing

## Purpose

The purpose of this document is to describe the why and how of the sandboxing approach we're taking.

## Why?

We have always known we need to put customer containers in a sandbox. This enables several important properties and capabilities:
- preventing access from DOSing Google APIs
- reduced risk of escape to hosts for malicious customer workloads
- moving KMS interactions and other common operations outside of user containers for more portability
- running docker compose
- gating access to keys and other private material with policies
- enabling trusted code to run inside of workloads to have access to network traffic and other things possibly for liveness guarantees
- more

The key reason for accelerating this effort is that out self service release is blocked on "preventing access from DOSing Google APIs", since attestations are ratelimited at a project level rather than an instance level in CS. Without gating access to APIs, one malicious workload could prevent any other attestations (including launch attestations!) from being generated. After much back and forth with Google, it seems as though sandboxing could be the fastest way to unblocking this and it is already on our roadmap.

Our goals for the initial version of sandboxing are
- preventing DOSing Google APIs
- move KMS logic into the sandboxer and use runtime attestations so we can make launch attestations public

## How?

We sandbox by running a special "sandboxer" container as the CS workload container. This sandboxer container is passed in the actual customer workload container as an overridden `IMAGE` environment variable. The sandboxer starts a containerd daemon and then pulls and starts the customer `IMAGE` using containerd's `ctr` CLI with a gVisor (runsc) runtime configuration.

The current implementation uses `ctr` (containerd's basic CLI) since nerdctl/docker/podman all ran into several issues with cgroups and networking.

The POC successfully demonstrates:
- Blocking access to the TEE server socket
- Port exposure and ingress to inner containers via iptables
- Internet egress from sandboxed containers
- Dynamic port detection from container images
- gVisor integration with host networking

### Limitations of `ctr` Approach

**Resource Management:**
- **Memory/CPU limits**: Possible but require manual cgroup configuration - not automatic like Docker's `--memory` or `--cpus` flags
- **Resource enforcement**: Must be explicitly configured through cgroup parameters, no built-in guardrails

**Networking:**
- **No network isolation**: Container uses `--network=host`, sharing the host's network namespace - no network-level sandboxing
- **Port publishing**: No automatic port mapping - requires manual iptables rules (current implementation)
- **Container-to-container networking**: Using host networking as workaround - no bridge networks or container DNS resolution
- **Security implication**: Sandboxed workloads can see all network interfaces and ports on the host, though gVisor still provides process/filesystem isolation

**Operational Features:**
- **No Docker Compose support**: Multi-container applications require custom orchestration
- **No container logs command**: Logs must be redirected to files and monitored separately (current implementation)
- **No automatic restart policies**: Containers don't restart on failure without custom logic
- **Volume management**:
  - Bind mounts work (mounting host directories into containers)
  - No named volumes - can't create managed volumes like `docker volume create`
  - No volume drivers - can't use cloud storage or distributed filesystem volumes
  - No volume lifecycle management - can't list, inspect, or clean up volumes
  - Data persistence between container restarts requires manual bind mount setup

**Production Considerations:**
- `ctr` is explicitly unsupported for production use by containerd maintainers
- Commands/options not guaranteed to be stable across containerd versions
- Designed as a debug tool, not a container orchestrator

**Alternative:** Switching to `nerdctl` would provide Docker-like features (Compose, resource limits, networking, logs) but requires resolving cgroup delegation and gVisor networking compatibility in the Confidential Space environment.

Performance is the main consideration (outside of the thing actually working) with this new scheme.

There are several other things required to get this to production:
- since the sandboxer must be trusted by all containers, it must be verifiably built (either with reproducible or reputably attested builds)
- the KMS server and other attestation parsers must be aware that the image ref in the attestation will be the sandboxer and the user's workload image will be an environment variable
- the KMS server and client need to be updated to use runtime attestations
- the CLI needs to be altered to not include KMS layering