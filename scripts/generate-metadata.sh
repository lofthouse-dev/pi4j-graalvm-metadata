#!/usr/bin/env bash
# Run the Pi4J FFM probe inside the graalvm-pi-builder container with the native-image-agent.
# Assumes the probe JAR is already built.
#
# Usage: generate-metadata.sh [output-dir]
#   output-dir: directory where reachability-metadata.json is written
#   Default: <repo-root>/generated-config
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ghcr.io/lofthouse-dev/graalvm-pi-builder:latest"
OUTPUT_DIR="${1:-$REPO_ROOT/generated-config}"
PROBE_JAR="$REPO_ROOT/probe/target/probe.jar"
AGENT_FILTER="$REPO_ROOT/probe/src/main/resources/agent-filter.json"

if [[ ! -f "$PROBE_JAR" ]]; then
    echo "ERROR: Probe JAR not found at $PROBE_JAR"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Running probe with native-image-agent..."
echo "    Image:  $IMAGE"
echo "    Output: $OUTPUT_DIR"

podman run --rm \
  --platform linux/arm64 \
  -v "$PROBE_JAR":/probe/probe.jar:Z,ro \
  -v "$AGENT_FILTER":/probe/agent-filter.json:Z,ro \
  -v "$OUTPUT_DIR":/generated-config:Z \
  "$IMAGE" \
  java \
    -agentlib:native-image-agent=config-output-dir=/generated-config,access-filter-file=/probe/agent-filter.json \
    -jar /probe/probe.jar

echo "==> Generated: $OUTPUT_DIR/reachability-metadata.json"
