#!/bin/bash
# Build the NanoClaw agent container image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="nanoclaw-agent"
TAG="${1:-latest}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"

echo "Building NanoClaw agent container image..."
echo "Image: ${IMAGE_NAME}:${TAG}"

# Forward sandbox proxy settings so apt/npm inside the build can reach the
# internet when running inside a Docker Sandbox (MITM proxy at
# host.docker.internal:3128). Harmless outside a sandbox.
PROXY_ARGS=""
for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  if [ -n "${!var:-}" ]; then
    PROXY_ARGS="$PROXY_ARGS --build-arg $var=${!var}"
  fi
done

# If a proxy is active, disable npm strict-ssl for the build (MITM cert won't
# be in the base image trust store). Runtime trust is re-enabled inside the
# image.
if [ -n "${http_proxy:-${HTTP_PROXY:-}}" ]; then
  PROXY_ARGS="$PROXY_ARGS --build-arg npm_config_strict_ssl=false"
fi

${CONTAINER_RUNTIME} build $PROXY_ARGS -t "${IMAGE_NAME}:${TAG}" .

echo ""
echo "Build complete!"
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""
echo "Test with:"
echo "  echo '{\"prompt\":\"What is 2+2?\",\"groupFolder\":\"test\",\"chatJid\":\"test@g.us\",\"isMain\":false}' | ${CONTAINER_RUNTIME} run -i ${IMAGE_NAME}:${TAG}"
