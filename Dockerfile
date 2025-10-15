FROM alpine:latest

# TEE labels must be in the final stage
LABEL tee.launch_policy.log_redirect=always
LABEL tee.launch_policy.allow_env_override=IMAGE
LABEL tee.launch_policy.allow_cgroups=true
LABEL tee.launch_policy.allow_capabilities=true

# Install containerd, nerdctl, CNI plugins, and dependencies
RUN apk add --no-cache \
    containerd \
    containerd-ctr \
    bash \
    iptables \
    ip6tables \
    wget \
    ca-certificates

# Install nerdctl (Docker-compatible CLI for containerd)
RUN wget -q https://github.com/containerd/nerdctl/releases/download/v1.7.7/nerdctl-1.7.7-linux-amd64.tar.gz && \
    tar -xzf nerdctl-1.7.7-linux-amd64.tar.gz -C /usr/local/bin/ && \
    rm nerdctl-1.7.7-linux-amd64.tar.gz

# Install CNI plugins for networking
RUN wget -q https://github.com/containernetworking/plugins/releases/download/v1.5.1/cni-plugins-linux-amd64-v1.5.1.tgz && \
    mkdir -p /opt/cni/bin && \
    tar -xzf cni-plugins-linux-amd64-v1.5.1.tgz -C /opt/cni/bin && \
    rm cni-plugins-linux-amd64-v1.5.1.tgz

# Install runsc (gVisor runtime)
RUN wget -q https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/runsc && \
    chmod +x runsc && \
    mv runsc /usr/local/bin/

# Create containerd config directory
RUN mkdir -p /etc/containerd

# Copy the runner script
COPY run-container.sh /usr/local/bin/run-container.sh
RUN chmod +x /usr/local/bin/run-container.sh

ENTRYPOINT ["/usr/local/bin/run-container.sh"]