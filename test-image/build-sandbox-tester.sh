#!/bin/bash

set -e

# get current dir
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR
TEST_IMAGE_REF="docker.io/saucelord/sandbox-tester:latest"

echo "Building sandbox tester image..."
docker build --platform linux/amd64 -f Dockerfile -t $TEST_IMAGE_REF .

echo ""
echo "Pushing to registry..."
docker push $TEST_IMAGE_REF

echo ""
echo "✓ Done: $TEST_IMAGE_REF"
echo ""
