#!/usr/bin/env bash
# Build the probe JAR then run it with native-image-agent to capture reachability metadata.
# Output: generated-config/reachability-metadata.json  (gitignored)
#
# Prerequisites:
#   - podman available on the host
#   - graalvm-pi-builder image built: make build-dev (in graalvm-pi-builder/)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building probe JAR..."
mvn -f "$REPO_ROOT/probe/pom.xml" --batch-mode package -q

"$REPO_ROOT/scripts/generate-metadata.sh"

echo ""
echo "==> Done. Generated metadata:"
ls -lh "$REPO_ROOT/generated-config/"
