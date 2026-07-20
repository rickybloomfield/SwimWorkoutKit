#!/bin/bash
# Publish a workout export as a shared catalog.
#
# Usage: Scripts/update-catalog.sh <export.swimworkouts> [catalog-id]
#
# Copies the archive into docs/catalog/<id>.swimworkouts and updates its
# manifest entry in docs/catalog/index.json in one step: bumps `version`
# (which is what tells apps to auto-sync), refreshes `workoutCount`, and
# stamps `updated` with today's date. Commit and push the result.
set -euo pipefail

cd "$(dirname "$0")/.."

file="${1:?usage: update-catalog.sh <export.swimworkouts> [catalog-id]}"
id="${2:-ricky}"
manifest="docs/catalog/index.json"

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }
[[ -f "$manifest" ]] || { echo "error: $manifest not found" >&2; exit 1; }

format=$(jq -r '.format // empty' "$file" 2>/dev/null) \
    || { echo "error: $file is not valid JSON" >&2; exit 1; }
[[ "$format" == "open-swim-workout-archive" ]] \
    || { echo "error: $file is not an Open Swim Workout archive" >&2; exit 1; }
jq -e '.catalogs | any(.id == "'"$id"'")' "$manifest" >/dev/null \
    || { echo "error: no catalog with id \"$id\" in $manifest" >&2; exit 1; }

if jq -e '.images and (.images | length > 0)' "$file" >/dev/null; then
    echo "error: export includes photos — re-export with photos off" >&2
    exit 1
fi

count=$(jq '.workouts | length' "$file")
cp "$file" "docs/catalog/$id.swimworkouts"

jq --arg id "$id" --arg count "$count" --arg today "$(date +%F)" '
    .catalogs |= map(if .id == $id then
        .version = (((.version // "0") | tonumber) + 1 | tostring)
        | .workoutCount = ($count | tonumber)
        | .updated = $today
    else . end)
' "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"

version=$(jq -r --arg id "$id" '.catalogs[] | select(.id == $id).version' "$manifest")
echo "Published $count workouts as catalog \"$id\" version $version."
echo "Review, commit, and push to deploy."
