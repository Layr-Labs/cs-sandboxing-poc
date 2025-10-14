#!/bin/bash

set -e

TEST_IMAGE_REF="docker.io/saucelord/cs-basic-test:latest"

echo "Building basic test image..."
docker build --platform linux/amd64 -f Dockerfile.test-basic -t $TEST_IMAGE_REF .

echo ""
echo "Pushing to registry..."
docker push $TEST_IMAGE_REF

echo ""
echo "✓ Done: $TEST_IMAGE_REF"
echo ""
echo "Deploy with:"
echo "  ./cloud.sh create gs-basic-test $TEST_IMAGE_REF"
