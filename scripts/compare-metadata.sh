#!/usr/bin/env bash
# Compare the reachability-metadata.json of the latest release with a freshly generated one.
#
# Usage: compare-metadata.sh <released.json> <generated.json>
#
# The comparison is normalised, so a change in formatting, in the order of object keys, or in the
# order of the entries of a collection is not reported as a difference. Collections are arrays whose
# elements are all objects (the downcall and resource lists); their order has no meaning.
# Arrays of scalars are positional and are NOT sorted: parameterTypes is a signature, so
# (jint, jlong) and (jlong, jint) are different downcalls.
#
# Exit status:
#   0  identical (byte-for-byte, or the same content once normalised)
#   1  the content differs (a unified diff of the normalised files is printed)
#   2  usage error, or an input that is missing, empty or not a valid JSON object
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $(basename "$0") <released.json> <generated.json>" >&2
    exit 2
fi
RELEASED="$1"
GENERATED="$2"

for f in "$RELEASED" "$GENERATED"; do
    if [[ ! -s "$f" ]]; then
        echo "ERROR: $f does not exist or is empty" >&2
        exit 2
    fi
done

# Validate both inputs before anything else, including before the byte-equality shortcut: two
# identical but corrupt files (an error page, a truncated download) must not pass as "identical
# metadata". The metadata is a JSON object.
for f in "$RELEASED" "$GENERATED"; do
    if ! jq -e 'type == "object"' "$f" > /dev/null 2>&1; then
        echo "ERROR: $f is not a valid JSON object" >&2
        exit 2
    fi
done

if cmp -s "$RELEASED" "$GENERATED"; then
    echo "RESULT: identical (byte-for-byte)"
    exit 0
fi

normalise() {
    jq -S '
      def canon_keys: walk(if type == "object" then (to_entries | sort_by(.key) | from_entries) else . end);
      canon_keys
      | walk(if type == "array" and length > 0 and all(.[]; type == "object")
             then sort_by(tojson) else . end)' "$1"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

normalise "$RELEASED" > "$TMP/released.json"
normalise "$GENERATED" > "$TMP/generated.json"

if cmp -s "$TMP/released.json" "$TMP/generated.json"; then
    echo "RESULT: identical content (only formatting or ordering differs)"
    exit 0
fi

echo "RESULT: DIFFERENT - the captured metadata no longer matches the latest release"
echo
echo "Unified diff of the normalised files (sorted keys and collections; - released, + generated):"
diff -u --label released --label generated "$TMP/released.json" "$TMP/generated.json" || true
exit 1
