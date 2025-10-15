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

We sandbox by running a special "sandboxer" container as the CS workload container. This sandboxer container is passed in the actual customer workload container as an overidden `IMAGE` environment variable. The sandboxer starts a containerd daemon and then pulls and starts the customer `IMAGE` via [nerdctl](https://github.com/containerd/nerdctl) using a gvisor runtime config. The current POC proves that we can block access to the teeserver socket, but not to the open internet. We are working on verifying that ports can be exposed for ingress to the inner container before continuing. UPDATE: i have gotten this working, but am working on de-vibe-coding

Performance is the main consideration (outside of the thing actually working) with this new scheme.

There are several other things required to get this to production:
- since the sandboxer must be trusted by all containers, it must be verifiably built (either with reproducible or reputably attested builds)
- the KMS server and other attestation parsers must be aware that the image ref in the attestation will be the sandboxer and the user's workload image will be an environment variable
- the KMS server and client need to be updated to use runtime attestations
- the CLI needs to be altered to not include KMS layering