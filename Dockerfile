FROM alpine:latest

# TEE labels must be in the final stage
LABEL tee.launch_policy.log_redirect=always
LABEL tee.launch_policy.allow_env_override=IMAGE
LABEL tee.launch_policy.allow_cgroups=true
LABEL tee.launch_policy.allow_capabilities=true

# Install Docker, bash and dependencies
RUN apk add --no-cache docker bash

# Install runsc with proper architecture detection
RUN apk add --no-cache wget && \
    wget https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/runsc && \
    chmod +x runsc && \
    mv runsc /usr/local/bin/

# Configure Docker daemon to use runsc runtime with ignore-cgroups
RUN mkdir -p /etc/docker && \
    echo '{"runtimes": {"runsc": {"path": "/usr/local/bin/runsc", "runtimeArgs": ["--ignore-cgroups"]}}, "exec-opts": ["native.cgroupdriver=cgroupfs"]}' > /etc/docker/daemon.json

# Copy the runner script
COPY run-container.sh /usr/local/bin/run-container.sh
RUN chmod +x /usr/local/bin/run-container.sh

ENTRYPOINT ["/usr/local/bin/run-container.sh"]