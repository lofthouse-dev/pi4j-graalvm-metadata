#!/usr/bin/env bash
# Report newer versions of the inputs that feed the captured metadata. Report-only.
#
#   - Pi4J: compares pi4j.version in the parent pom.xml with the latest release of
#     com.pi4j:pi4j-core on Maven Central.
#   - graalvm-pi-builder: compares the tag pinned in graalvm-pi-builder.env with the newest
#     bookworm-<version> tag in GHCR.
#
# Usage: check-updates.sh
#
# Prints one "- ..." line per newer version found and nothing when everything is current.
#
# Exit status:
#   0  both lookups completed (stdout lists any newer versions)
#   3  at least one lookup failed; reported as a ::warning:: on stderr. Findings from the lookups
#      that did succeed are still printed. A caller must not treat "no output" as "up to date" in
#      this case, so a network problem can neither raise nor close a report by itself.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INCOMPLETE=0
warn() { echo "::warning::check-updates: $*" >&2; INCOMPLETE=1; }

# True when $1 is a strictly lower version than $2 (version sort).
older() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]
}

# --- Pi4J ----------------------------------------------------------------------------------------
CURRENT_PI4J="$(sed -n 's|.*<pi4j.version>\(.*\)</pi4j.version>.*|\1|p' "$REPO_ROOT/pom.xml" | head -n 1)"
if [[ -z "$CURRENT_PI4J" ]]; then
    warn "could not read pi4j.version from pom.xml"
elif LATEST_PI4J="$(curl -fsS https://repo1.maven.org/maven2/com/pi4j/pi4j-core/maven-metadata.xml \
        | sed -n 's|.*<release>\(.*\)</release>.*|\1|p' | head -n 1)" && [[ -n "$LATEST_PI4J" ]]; then
    if older "$CURRENT_PI4J" "$LATEST_PI4J"; then
        echo "- Newer Pi4J available: $LATEST_PI4J (pi4j.version is $CURRENT_PI4J). Update the \`pi4j.version\` property and the project version prefix, see RELEASING.md."
    fi
else
    warn "could not look up the latest Pi4J release on Maven Central"
fi

# --- graalvm-pi-builder ----------------------------------------------------------------------------
PINNED_IMAGE="$(. "$REPO_ROOT/graalvm-pi-builder.env" && printf '%s' "${GRAALVM_PI_BUILDER_IMAGE:-}")"
if [[ -z "$PINNED_IMAGE" || "$PINNED_IMAGE" != *:* ]]; then
    warn "could not read GRAALVM_PI_BUILDER_IMAGE from graalvm-pi-builder.env"
else
    PINNED_TAG="${PINNED_IMAGE##*:}"
    IMAGE_PATH="${PINNED_IMAGE%:*}"      # ghcr.io/<owner>/<name>
    IMAGE_PATH="${IMAGE_PATH#ghcr.io/}"  # <owner>/<name>
    TOKEN="$(curl -fsS "https://ghcr.io/token?scope=repository:${IMAGE_PATH}:pull" | jq -r '.token // empty')"
    if [[ -z "$TOKEN" ]]; then
        warn "could not get a GHCR pull token for $IMAGE_PATH"
    elif TAGS="$(curl -fsS -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/${IMAGE_PATH}/tags/list?n=1000" \
            | jq -r '.tags[]?')" && [[ -n "$TAGS" ]]; then
        # Version-pinned tags only: bookworm-<number>(.<number>)+ ; not -YYYYMMDD snapshots,
        # which have a further "-" part, and not the mutable bookworm-graalNN tag.
        NEWEST_TAG="$(printf '%s\n' "$TAGS" | grep -E '^bookworm-[0-9]+(\.[0-9]+)+$' | sort -V | tail -n 1)"
        if [[ -n "$NEWEST_TAG" ]] && older "${PINNED_TAG#bookworm-}" "${NEWEST_TAG#bookworm-}"; then
            echo "- Newer graalvm-pi-builder available: \`$NEWEST_TAG\` (pinned: \`$PINNED_TAG\`). Update \`graalvm-pi-builder.env\`, then check whether the captured metadata changes."
        fi
    else
        warn "could not list the tags of $IMAGE_PATH in GHCR"
    fi
fi

if [[ "$INCOMPLETE" -ne 0 ]]; then
    exit 3
fi
exit 0
