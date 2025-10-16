FROM alpine:latest

# TEE labels must be in the final stage
LABEL tee.launch_policy.log_redirect=always
LABEL tee.launch_policy.allow_env_override=IMAGE
LABEL tee.launch_policy.allow_cgroups=true
LABEL tee.launch_policy.allow_capabilities=true

# Install containerd, containerd, CNI plugins, and dependencies
RUN apk add --no-cache \
    containerd \
    containerd-ctr \
    bash \
    iptables \
    wget \
    ca-certificates \
    jq \
    grep \
    curl

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

# Copy scripts
COPY test.sh /usr/local/bin/test.sh
RUN chmod +x /usr/local/bin/test.sh

# Expose port 8080 for external access
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/test.sh"]