#!/usr/bin/env bash
# Provenance gate for this package: every upstream byte it carries, checked
# against the pin recorded in UPSTREAM-BASELINE.sha256.
#
# Usage: ./check-upstream-baseline.sh     (run from anywhere; it cds to its own
#                                         directory, which is the repository root)
#
# Five questions, none of which needs a compiler, a build or the network:
#
#   1. Does every carried upstream file still hash to the pinned upstream?
#   2. Is every recorded divergence still exactly the recorded bytes, and does
#      it still differ from the pin in the way the record says it does?
#   3. Are the counts and the per-area counts in the record the counts in the
#      file, so the record cannot describe a tree that no longer exists?
#   4. Is every carried path that is not upstream declared fork-owned, so an
#      unrecorded file cannot appear in a directory the record already covers?
#   5. Do the fork's verbatim copies still match the upstream file they copy,
#      and does the pin still agree with UPSTREAM.md?
#
# `sha256sum -c UPSTREAM-BASELINE.sha256` answers question 1 alone. That is the
# narrower check, and this script exists because the narrower one cannot tell
# a complete baseline from one that stopped covering the tree.
#
# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Fork-authored. FORK-LICENSE.md records the owner's authorization of that
# grant; UPSTREAM-BASELINE.sha256 is the record this script verifies and
# UPSTREAM.md states the pin it was derived from.

set -euo pipefail

cd "$(dirname "$0")"
record=UPSTREAM-BASELINE.sha256
failures=0

fail() {
    echo "provenance: $1" >&2
    failures=$((failures + 1))
}

if [ ! -s "$record" ]; then
    echo "provenance: $record is missing or empty; there is no baseline to check" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The manifest is the body: every line that is not a comment, in `sha256sum`
# format. `grep -v` rather than trusting `sha256sum -c` to skip the header, so
# that the file this script reads and the file it verifies are the same file.
grep -v '^#' "$record" >"$tmp/manifest.sha256"
sed -n 's/^# divergence: //p' "$record" >"$tmp/divergences"
sed -n 's/^# fork-owned-file: //p' "$record" >"$tmp/fork-files"
sed -n 's/^# fork-owned-prefix: //p' "$record" >"$tmp/fork-prefixes"
sed -n 's/^# verbatim-copy: //p' "$record" >"$tmp/verbatim-copies"
sed -n 's/^# pin-echo: //p' "$record" >"$tmp/pin-echoes"

manifest_count=$(wc -l <"$tmp/manifest.sha256")
divergence_count=$(wc -l <"$tmp/divergences")
cut -c67- "$tmp/manifest.sha256" | LC_ALL=C sort >"$tmp/manifest.paths"
cut -d' ' -f1 "$tmp/divergences" | LC_ALL=C sort >"$tmp/divergence.paths"

# ---------------------------------------------------------------------------
# 1. the carried bytes
# ---------------------------------------------------------------------------
if sha256sum -c --quiet --strict "$tmp/manifest.sha256" >"$tmp/manifest.log" 2>&1; then
    :
else
    sed 's/^/  /' "$tmp/manifest.log" >&2
    fail "a carried upstream file does not match the pin, or is missing; see the list above"
fi

# ---------------------------------------------------------------------------
# 2. the recorded divergences
# ---------------------------------------------------------------------------
while read -r path rest; do
    [ -n "$path" ] || continue
    upstream=${rest#*upstream=}; upstream=${upstream%% *}
    carried=${rest#*carried=}; carried=${carried%% *}
    ubytes=${rest#*upstream_bytes=}; ubytes=${ubytes%% *}
    cbytes=${rest#*carried_bytes=}; cbytes=${cbytes%% *}
    policy=${rest#*policy=}; policy=${policy%% *}
    if [ ! -f "$path" ]; then
        fail "$path is recorded as a divergence from the pin but is not in the tree"
        continue
    fi
    actual=$(sha256sum "$path" | cut -d' ' -f1)
    if [ "$actual" != "$carried" ]; then
        fail "$path is a recorded divergence and its bytes changed"
        echo "  recorded $carried" >&2
        echo "  actual   $actual" >&2
    fi
    case "$policy" in
        upstream-bytes-are-a-prefix-of-carried)
            # The prefix property itself needs upstream's bytes, which this
            # script does not have; the repository's own `git diff --numstat`
            # step is what proves no upstream line was removed. What is checked
            # here is that the carried file still is the recorded one and is
            # still larger than the upstream file it extends.
            if [ "$cbytes" -le "$ubytes" ]; then
                fail "$path is recorded as upstream-plus-additions but is not larger than upstream"
            fi
            ;;
        *)
            fail "$path is recorded with the unknown divergence policy '$policy'"
            ;;
    esac
    echo "  recorded divergence, unchanged: $path ($upstream at the pin)"
done <"$tmp/divergences"

# ---------------------------------------------------------------------------
# 3. the counts
# ---------------------------------------------------------------------------
stated_total=$(sed -n 's/^# count: carried upstream paths in this baseline = //p' "$record")
actual_total=$((manifest_count + divergence_count))
[ "$stated_total" = "$actual_total" ] ||
    fail "the record claims $stated_total carried upstream paths and contains $actual_total"

stated_identical=$(sed -n 's/^# count: byte-identical to the pin = //p' "$record")
[ "$stated_identical" = "$manifest_count" ] ||
    fail "the record claims $stated_identical byte-identical paths and lists $manifest_count"

stated_div=$(sed -n 's/^# count: recorded divergences from the pin = //p' "$record")
[ "$stated_div" = "$divergence_count" ] ||
    fail "the record claims $stated_div divergences and records $divergence_count"

stated_mpfr=$(sed -n 's/^# count: GNU MPFR [0-9.a-z]* at [0-9a-f]* = //p' "$record")
actual_mpfr=$actual_total
[ "$stated_mpfr" = "$actual_mpfr" ] ||
    fail "the record claims $stated_mpfr MPFR paths and carries $actual_mpfr"

# per-area counts
cat "$tmp/manifest.paths" "$tmp/divergence.paths" >"$tmp/baseline.paths"
while read -r path; do
    case "$path" in
        */*) label=${path%%/*} ;;
        *) label=root ;;
    esac
    echo "$label"
done <"$tmp/baseline.paths" | LC_ALL=C sort | uniq -c |
    awk '{ printf "# area: %s = %s\n", $2, $1 }' >"$tmp/areas.actual"
sed -n 's/^\(# area: .* = [0-9]*\)$/\1/p' "$record" | LC_ALL=C sort >"$tmp/areas.stated"
if ! diff -u "$tmp/areas.stated" "$tmp/areas.actual" >"$tmp/areas.diff"; then
    sed 's/^/  /' "$tmp/areas.diff" >&2
    fail "the per-area counts in the record are not the counts in its manifest"
fi

# ---------------------------------------------------------------------------
# 4. coverage in the other direction
# ---------------------------------------------------------------------------
# Build outputs and the version-control directory are not carried bytes.
find . \( -name .git -o -name .zig-cache -o -name zig-out -o -name zig-pkg \) -prune -o -type f -print |
    sed 's#^\./##' | LC_ALL=C sort >"$tmp/carried"

cat "$tmp/manifest.paths" "$tmp/divergence.paths" "$tmp/fork-files" >"$tmp/known"
LC_ALL=C sort -u -o "$tmp/known" "$tmp/known"

awk 'NR == FNR { pfx[$0] = 1; next }
     {
         path = $0
         drop = 0
         for (p in pfx) {
             n = length(p)
             if (length(path) >= n && substr(path, 1, n) == p) { drop = 1; break }
         }
         if (!drop) print path
     }' "$tmp/fork-prefixes" "$tmp/carried" >"$tmp/carried.not-prefix"

LC_ALL=C comm -23 "$tmp/carried.not-prefix" "$tmp/known" >"$tmp/unaccounted"
if [ -s "$tmp/unaccounted" ]; then
    sed 's/^/  /' "$tmp/unaccounted" >&2
    fail "a carried path is neither upstream nor declared fork-owned; if it is fork work, add it as a 'fork-owned-file:' or 'fork-owned-prefix:' line in $record"
fi

carried_fork=$(( $(wc -l <"$tmp/carried") - actual_total ))
stated_fork=$(sed -n 's/^# count: fork-owned paths carried alongside (excluded below) = //p' "$record")
[ "$stated_fork" = "$carried_fork" ] ||
    fail "the record claims $stated_fork fork-owned carried paths and the tree carries $carried_fork"

# A declared fork file that is gone is a stale record, which is the same defect
# in the other direction.
while read -r path; do
    [ -n "$path" ] || continue
    [ -f "$path" ] || fail "$record declares $path fork-owned but the file is not in the tree"
done <"$tmp/fork-files"

# ---------------------------------------------------------------------------
# 5. verbatim copies, and agreement with UPSTREAM.md
# ---------------------------------------------------------------------------
while read -r copy equals source; do
    [ -n "$copy" ] || continue
    if [ "$equals" != "=" ]; then
        fail "'$copy $equals $source' is not a 'copy = source' declaration"
        continue
    fi
    if [ ! -f "$copy" ]; then
        fail "the verbatim copy $copy is missing"
        continue
    fi
    want=$(awk -v p="$source" '$2 == p { print $1 }' "$tmp/manifest.sha256")
    if [ -z "$want" ]; then
        fail "$source is not in the baseline, so $copy cannot be checked against it"
        continue
    fi
    got=$(sha256sum "$copy" | cut -d' ' -f1)
    [ "$got" = "$want" ] ||
        fail "$copy is not a byte-for-byte copy of $source any more"
done <"$tmp/verbatim-copies"

if [ ! -s UPSTREAM.md ]; then
    fail "UPSTREAM.md is missing or empty; the pin has nothing to agree with"
else
    while read -r line; do
        [ -n "$line" ] || continue
        # The value is what precedes the parenthetical explanation, so a pin
        # whose value contains spaces is checked whole rather than by its
        # first word.
        value=${line%% (*}
        value=${value% }
        grep -Fq "$value" UPSTREAM.md ||
            fail "$value is pinned in $record but UPSTREAM.md does not state it"
    done <"$tmp/pin-echoes"
fi

# ---------------------------------------------------------------------------
if [ "$failures" -ne 0 ]; then
    echo "provenance: $failures check(s) failed" >&2
    exit 1
fi

echo "upstream baseline verified: $actual_total carried upstream paths"
echo "  GNU MPFR 4.2.2      $actual_mpfr paths"
echo "  byte-identical      $manifest_count"
echo "  recorded divergence $divergence_count"
echo "  fork-owned          $carried_fork paths carried alongside"
echo "every pin value in $record also appears in UPSTREAM.md"