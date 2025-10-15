FROM alpine:latest

# TEE labels
LABEL tee.launch_policy.log_redirect=always
LABEL tee.launch_policy.allow_env_override=IMAGE

# Install basic tools
RUN apk add --no-cache bash

# Copy test script
COPY test.sh /test.sh
RUN chmod +x /test.sh

CMD ["/test.sh"]
