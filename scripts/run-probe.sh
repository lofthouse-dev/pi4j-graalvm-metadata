#!/usr/bin/env bash
# Run the Pi4J FFM probe inside the graalvm-pi-builder container with the native-image-agent
# to capture reachability metadata for all FunctionDescriptor downcalls.
#
# Prerequisites:
#   - podman available on the host
#   - graalvm-pi-builder image built: make build-dev (in graalvm-pi-builder/)
#   - probe JAR built: mvn -pl probe package (or run this script which does it)
#
# Output: generated-config/reachability-metadata.json
# This directory is gitignored — it is transient build output.
# Copy the JSON to metadata/src/main/resources/META-INF/native-image/com.pi4j/pi4j-plugin-ffm/
# before building the metadata module.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ghcr.io/lofthouse-dev/graalvm-pi-builder:latest"
OUTPUT_DIR="$REPO_ROOT/generated-config"
PROBE_JAR="$REPO_ROOT/probe/target/probe.jar"
AGENT_FILTER="$REPO_ROOT/probe/src/main/resources/agent-filter.json"

echo "==> Building probe JAR..."
mvn -f "$REPO_ROOT/probe/pom.xml" --batch-mode package -q

if [[ ! -f "$PROBE_JAR" ]]; then
    echo "ERROR: Probe JAR not found at $PROBE_JAR"
    exit 1
fi

rm -rf "$OUTPUT_DIR"
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

echo ""
echo "==> Done. Generated metadata:"
ls -lh "$OUTPUT_DIR/"
