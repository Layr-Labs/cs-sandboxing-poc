# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY main.go go.mod go.sum ./

# Build the Go binary
RUN CGO_ENABLED=0 GOOS=linux go build -o test-app .

# Runtime stage
FROM alpine:latest

# Install necessary tools for diagnostics
RUN apk add --no-cache \
    bash \
    curl \
    iproute2 \
    bind-tools \
    iputils \
    libcap

# Copy the binary from builder
COPY --from=builder /build/test-app /test-app

# Expose port for health checks
EXPOSE 8080

CMD ["/test-app"]
