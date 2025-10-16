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

We sandbox by running a special "sandboxer" container as the CS workload container. This sandboxer container is passed in the actual customer workload container as an overridden `IMAGE` environment variable. The sandboxer starts a containerd daemon and then pulls and starts the customer `IMAGE` using `nerdctl` (a Docker-compatible CLI for containerd) with a gVisor (runsc) runtime configuration.

### Current Implementation: `nerdctl`

The current implementation uses `nerdctl` with the following configuration:
- **Snapshotter**: Native snapshotter (`--snapshotter=native`) for gVisor compatibility
- **Runtime**: Custom runsc wrapper with host networking (`--runtime=runsc-host`)
- **Networking**: Host networking mode (`--net=host`)

The POC successfully demonstrates:
- Blocking access to the TEE server socket
- Port exposure and ingress to inner containers via iptables
- Internet egress from sandboxed containers
- Dynamic port detection from container images
- gVisor integration with host networking
- Docker-compatible commands and features

### Limitations of Current Approach

**Networking:**
- **No network isolation**: Containers use `--net=host`, sharing the host's network namespace - no network-level sandboxing
- **Security implication**: Sandboxed workloads can see all network interfaces and ports on the host, though gVisor still provides process/filesystem isolation
- **Port publishing**: Requires manual iptables rules (current implementation handles this automatically based on EXPOSE directives)
- **Container-to-container networking**: No bridge networks or container DNS resolution between multiple containers

**What Works (thanks to nerdctl):**
- **Docker Compose support**: `nerdctl compose` for multi-container applications
- **Container logs**: `nerdctl logs` command available
- **Automatic restart policies**: `nerdctl run --restart` supported
- **Volume management**: Full support for named volumes, volume drivers, lifecycle management
- **Resource limits**: Native support for `--memory`, `--cpus`, and other resource flags
- **Production ready**: nerdctl is actively maintained and production-supported
- **Stability**: Guaranteed API compatibility with Docker CLI

Performance is the main consideration (outside of the thing actually working) with this new scheme.

There are several other things required to get this to production:
- since the sandboxer must be trusted by all containers, it must be verifiably built (either with reproducible or reputably attested builds)
- the KMS server and other attestation parsers must be aware that the image ref in the attestation will be the sandboxer and the user's workload image will be an environment variable
- the KMS server and client need to be updated to use runtime attestations
- the CLI needs to be altered to not include KMS layering