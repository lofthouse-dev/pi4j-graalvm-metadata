#!/usr/bin/env bash
# Extract reachability-metadata.json from the jar of the most recent release.
#
# Usage: fetch-released-metadata.sh <output-file>
#
# The most recent release is the highest version tag (releases are tagged with the bare Maven
# version, e.g. 4.0.2-0; history is linear). Run from a checkout that has the tags.
#
# The jar is downloaded from GitHub Packages with GITHUB_ACTOR and GITHUB_TOKEN (the token needs
# packages: read). For testing without a token, set RELEASED_JAR to a local copy of the jar.
#
# Prints the release version as the last line of stdout. Nothing else is written to stdout.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $(basename "$0") <output-file>" >&2
    exit 2
fi
OUTPUT="$1"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="META-INF/native-image/com.pi4j/pi4j-plugin-ffm/reachability-metadata.json"
OWNER_REPO="${GITHUB_REPOSITORY:-lofthouse-dev/pi4j-graalvm-metadata}"

VERSION="$(git -C "$REPO_ROOT" tag --list '[0-9]*' --sort=-v:refname | head -n 1)"
if [[ -z "$VERSION" ]]; then
    echo "ERROR: no release tag found (is this a full clone with tags? use fetch-depth: 0)" >&2
    exit 1
fi

# The artifactId is read from the release's own pom (at its tag), not the current checkout: after
# a major GraalVM upgrade (graal25 -> graal26) the current pom names an artifact that the latest
# release does not contain.
ARTIFACT_ID="$(git -C "$REPO_ROOT" show "${VERSION}:metadata/pom.xml" \
    | sed -n 's|.*<artifactId>\(pi4j-ffm-metadata-bookworm-graal[0-9]*\)</artifactId>.*|\1|p' | head -n 1)"
if [[ -z "$ARTIFACT_ID" ]]; then
    echo "ERROR: could not read the metadata artifactId from metadata/pom.xml at tag $VERSION" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
JAR="$TMP/released.jar"

if [[ -n "${RELEASED_JAR:-}" ]]; then
    echo "Using local jar $RELEASED_JAR instead of downloading $VERSION" >&2
    cp "$RELEASED_JAR" "$JAR"
else
    : "${GITHUB_TOKEN:?GITHUB_TOKEN is required to download from GitHub Packages}"
    : "${GITHUB_ACTOR:?GITHUB_ACTOR is required to download from GitHub Packages}"
    URL="https://maven.pkg.github.com/${OWNER_REPO}/dev/lofthouse/pi4j/${ARTIFACT_ID}/${VERSION}/${ARTIFACT_ID}-${VERSION}.jar"
    echo "Downloading $URL" >&2
    if ! curl -fsSL -u "${GITHUB_ACTOR}:${GITHUB_TOKEN}" -o "$JAR" "$URL"; then
        echo "ERROR: could not download the jar for the latest tag $VERSION." >&2
        echo "       A 404 means the tag exists but the publish workflow did not deploy it;" >&2
        echo "       a 401/403 means the token cannot read packages (e.g. a PR from a fork)." >&2
        exit 1
    fi
fi

if ! unzip -p "$JAR" "$ENTRY" > "$OUTPUT" 2>/dev/null || [[ ! -s "$OUTPUT" ]]; then
    echo "ERROR: $ENTRY not found in the jar for $VERSION" >&2
    exit 1
fi

echo "$VERSION"
