#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 <legacy-data-folder> <output.json> [daily-review-limit] [relearn-delay-minutes]" >&2
  exit 64
fi

legacy_dir=$1
output_file=$2
daily_review_limit=${3:-20}
relearn_delay_minutes=${4:-10}
database_file="$legacy_dir/quickdict.sqlite"

if [[ ! -f "$database_file" ]]; then
  echo "Missing legacy database: $database_file" >&2
  exit 66
fi

if [[ -e "$output_file" ]]; then
  echo "Refusing to overwrite existing backup: $output_file" >&2
  exit 73
fi

if ! [[ "$daily_review_limit" =~ ^[0-9]+$ ]] || (( daily_review_limit < 1 || daily_review_limit > 100 )); then
  echo "Daily review limit must be an integer from 1 to 100" >&2
  exit 64
fi

if ! [[ "$relearn_delay_minutes" =~ ^[0-9]+$ ]] || (( relearn_delay_minutes < 1 || relearn_delay_minutes > 240 )); then
  echo "Relearn delay must be an integer from 1 to 240" >&2
  exit 64
fi

snapshot_dir=$(mktemp -d "${TMPDIR:-/tmp}/quickdict-legacy-export.XXXXXX")
cleanup() {
  rm -rf "$snapshot_dir"
}
trap cleanup EXIT

for filename in quickdict.sqlite quickdict.sqlite-wal quickdict.sqlite-shm; do
  if [[ -f "$legacy_dir/$filename" ]]; then
    cp -p "$legacy_dir/$filename" "$snapshot_dir/$filename"
  fi
done

favorites_json="$snapshot_dir/favorites.json"
history_json="$snapshot_dir/history.json"
output_tmp="$snapshot_dir/backup.json"

sqlite3 -readonly -json "$snapshot_dir/quickdict.sqlite" > "$favorites_json" <<'SQL'
SELECT id,
       word,
       sentence,
       added_at AS addedAt,
       ease,
       interval_days AS intervalDays,
       due_at AS dueAt,
       review_count AS reviewCount,
       last_review AS lastReview,
       tags,
       context_sentence AS contextSentence,
       definition_snapshot AS definitionSnapshot,
       note
FROM favorites
ORDER BY added_at ASC;
SQL

sqlite3 -readonly -json "$snapshot_dir/quickdict.sqlite" > "$history_json" <<'SQL'
SELECT word,
       lookup_count AS lookupCount,
       first_at AS firstAt,
       last_at AS lastAt,
       last_context AS lastContext
FROM history
ORDER BY last_at DESC;
SQL

exported_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
mkdir -p "$(dirname "$output_file")"

jq -S -n \
  --slurpfile favorites "$favorites_json" \
  --slurpfile history "$history_json" \
  --arg exportedAt "$exported_at" \
  --argjson dailyReviewLimit "$daily_review_limit" \
  --argjson relearnDelayMinutes "$relearn_delay_minutes" '
    def iso8601:
      if . == null then null else (floor | todateiso8601) end;
    def without_nulls:
      with_entries(select(.value != null));
    {
      schemaVersion: 1,
      exportedAt: $exportedAt,
      favorites: ($favorites[0] | map({
        id,
        word,
        sentence,
        addedAt: (.addedAt | iso8601),
        ease,
        intervalDays,
        dueAt: (.dueAt | iso8601),
        reviewCount,
        lastReview: (.lastReview | iso8601),
        tags,
        contextSentence,
        definitionSnapshot,
        note
      } | without_nulls)),
      history: ($history[0] | map({
        word,
        lookupCount,
        firstAt: (.firstAt | iso8601),
        lastAt: (.lastAt | iso8601),
        lastContext
      } | without_nulls)),
      settings: {
        dailyReviewLimit: $dailyReviewLimit,
        relearnDelayMinutes: $relearnDelayMinutes
      }
    }
  ' > "$output_tmp"

jq -e '
  .schemaVersion == 1
  and (.favorites | type == "array")
  and (.history | type == "array")
  and (.settings.dailyReviewLimit | type == "number")
  and (.settings.relearnDelayMinutes | type == "number")
' "$output_tmp" >/dev/null

install -m 600 "$output_tmp" "$output_file"
printf 'Exported %s favorites and %s history entries to %s\n' \
  "$(jq '.favorites | length' "$output_file")" \
  "$(jq '.history | length' "$output_file")" \
  "$output_file"
