FROM alpine:latest

# Install basic tools
RUN apk add --no-cache bash curl

# Copy test script
COPY test.sh /test.sh
RUN chmod +x /test.sh

CMD ["/test.sh"]
