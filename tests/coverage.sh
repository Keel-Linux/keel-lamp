#!/bin/bash
# Line coverage of the shell this recipe writes, measured with kcov over the
# bats suite (decision 0004). This recipe ships no first boot hook and no
# library of its own (the database password hook is the shared tree's), so the
# one file measured here is the logic of the boot test,
# tests/lib/boot-test-lib.sh; the 95 percent bar of decision 0003 applies to
# it. Exits 1 below the threshold, 2 when a tool is missing.
#
# tests/boot-test.sh is the thin main that runs keel and LXC as root and is
# exercised by the two container runs in test-appliance.yml, not measured
# here; conf.d/main is a build time script exercised by the build itself, and
# every line of it is an assertion, so a failed build names the thing that is
# wrong.
#
#   tests/coverage.sh [THRESHOLD]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
threshold="${1:-${COVERAGE_THRESHOLD:-100}}"

for tool in kcov bats python3; do
    if ! command -v "$tool" >/dev/null; then
        echo "$tool not found (apt-get install $tool)" >&2
        exit 2
    fi
done

report="${COVERAGE_DIR:-$(mktemp -d)}"
# The include pattern is the whitelist, so no exclude pattern is needed; an
# exclude of /tests/ would drop tests/lib/boot-test-lib.sh with it.
kcov --include-pattern=/tests/lib/boot-test-lib.sh \
    "$report" bats "$here"

json="$(find "$report" -mindepth 2 -maxdepth 2 -name coverage.json -not -path "*/kcov-merged/*" | head -1)"
echo
echo "kcov line coverage (threshold $threshold percent):"
awk -F'"' -v threshold="$threshold" '
    /^ *\{"file":/ {
        n = split($4, parts, "/")
        printf "%7.2f  %s/%s  %s", $8, $12, $16, parts[n]
        if ($8 + 0 < threshold) { printf "  BELOW THRESHOLD"; below = 1 }
        printf "\n"
        seen = 1
    }
    END {
        if (!seen) { print "no file measured"; exit 1 }
        exit below
    }' "$json"
