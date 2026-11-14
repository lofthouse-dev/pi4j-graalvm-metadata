#!/usr/bin/env bash
# Keep the single tracking issue for metadata drift and newer versions up to date.
#
# Usage: update-tracking-issue.sh <drift:true|false> <updates:true|false> <lookups-complete:true|false> <report-file> <run-url>
#
# There is exactly one tracking issue, found by its label rather than created per run. It is
# needed when the captured metadata differs from the latest release (drift) or when a newer Pi4J
# or graalvm-pi-builder is available (updates).
#
#   needed, no issue yet       create it
#   needed, issue open         refresh its body with the latest report (no comment, so no spam)
#   needed, issue closed       reopen it with a comment and refresh its body
#   not needed, issue open     comment that it is resolved, then close it
#   not needed, issue closed   nothing
#
# "Not needed" requires that the version lookups were complete. When a lookup failed and nothing
# is found, the state is unknown, so an open issue is left alone rather than closed.
#
# Requires the GitHub CLI (gh) with GH_TOKEN (issues: write) and GITHUB_REPOSITORY. Set
# DRY_RUN=1 to print the gh commands instead of running them; with DRY_RUN, EXISTING_ISSUE
# ("<number> <OPEN|CLOSED>" or empty) stands in for the lookup, so every case can be tested.
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $(basename "$0") <drift:true|false> <updates:true|false> <lookups-complete:true|false> <report-file> <run-url>" >&2
    exit 2
fi
DRIFT="$1"
UPDATES="$2"
COMPLETE="$3"
REPORT="$4"
RUN_URL="$5"

LABEL="metadata-drift"
TITLE="Pi4J metadata: release or version update needed"

run_gh() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        printf 'gh'; printf ' %q' "$@"; printf '\n'
    else
        gh "$@"
    fi
}

NEEDED=false
if [[ "$DRIFT" == "true" || "$UPDATES" == "true" ]]; then
    NEEDED=true
fi

if [[ -n "${DRY_RUN:-}" ]]; then
    EXISTING="${EXISTING_ISSUE:-}"
else
    EXISTING="$(gh issue list --label "$LABEL" --state all --limit 1 \
        --json number,state --jq '.[0] | select(. != null) | "\(.number) \(.state)"')"
fi
NUMBER="${EXISTING%% *}"
STATE="${EXISTING##* }"

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
{
    echo "Maintained automatically by the metadata drift workflow; the body is replaced on every run"
    echo "that needs attention, so this is always the latest report. Last updated by: $RUN_URL"
    echo
    if [[ "$DRIFT" == "true" ]]; then
        echo "## The captured metadata differs from the latest release"
        echo
        echo "A new metadata release is needed (see RELEASING.md); releases are always manual."
        echo
    fi
    cat "$REPORT"
} > "$BODY_FILE"

if [[ "$NEEDED" == "true" ]]; then
    if [[ -z "$EXISTING" ]]; then
        run_gh label create "$LABEL" --description "Metadata drift / version update report" \
            --color D93F0B 2>/dev/null || true
        run_gh issue create --title "$TITLE" --label "$LABEL" --body-file "$BODY_FILE"
    elif [[ "$STATE" == "OPEN" ]]; then
        run_gh issue edit "$NUMBER" --body-file "$BODY_FILE"
    else
        run_gh issue reopen "$NUMBER" --comment "Reopened: attention is needed again. See the updated description. Run: $RUN_URL"
        run_gh issue edit "$NUMBER" --body-file "$BODY_FILE"
    fi
elif [[ "$COMPLETE" != "true" ]]; then
    echo "Leaving the tracking issue as it is: a version lookup failed, so \"nothing to report\" is unknown."
else
    if [[ -n "$EXISTING" && "$STATE" == "OPEN" ]]; then
        run_gh issue close "$NUMBER" --reason completed \
            --comment "Resolved: the captured metadata matches the latest release and no newer Pi4J or graalvm-pi-builder is available. Run: $RUN_URL"
    else
        echo "Nothing to do: no attention needed and no open tracking issue."
    fi
fi
