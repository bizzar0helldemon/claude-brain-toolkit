#!/usr/bin/env bash
# Tests for tools/brain-gardener.py — decay/promotion transitions + event folding.
# Builds a synthetic vault with a pinned clock so every transition is deterministic.
set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GARDENER="$REPO_DIR/tools/brain-gardener.py"
NOW="2026-07-07"
PASS=0
FAIL=0

VAULT=$(mktemp -d)
trap 'rm -rf "$VAULT"' EXIT
mkdir -p "$VAULT/brain-mode" "$VAULT/prompts/meta" "$VAULT/handoffs" \
         "$VAULT/preferences" "$VAULT/synthesis" "$VAULT/daily_notes"

note() {  # note <relpath> <frontmatter-body>
  local rel="$1"; shift
  printf -- '---\n%s\n---\n\nbody\n' "$1" > "$VAULT/$rel"
}

# --- Fixtures ---------------------------------------------------------------
# A: warm note used twice this week -> should PROMOTE to hot
note "prompts/meta/promote-me.md" "title: Promote Me
type: prompt-pattern
project: demo
status: warm
created: 2026-07-01"

# B: hot note, surfaced 9x, never used -> should DEMOTE to warm
note "prompts/meta/shown-unused.md" "title: Shown Unused
type: prompt-pattern
project: demo
status: hot
created: 2026-06-01"

# C: warm note, idle 200 days, zero use -> should ARCHIVE
note "prompts/meta/ancient.md" "title: Ancient
type: prompt-pattern
project: demo
status: warm
created: 2025-12-01"

# D: archived note, idle way past tombstone window -> should TOMBSTONE
note "prompts/meta/fossil.md" "title: Fossil
type: prompt-pattern
project: demo
status: archive
created: 2025-01-01"

# E: archived note that gets used this week -> should RESURRECT
note "prompts/meta/comeback.md" "title: Comeback
type: prompt-pattern
project: demo
status: archive
created: 2025-06-01"

# F: preference note idle forever -> EXEMPT, must stay put
note "preferences/user-model.md" "title: User Model
type: preference
scope: global
status: hot
created: 2025-01-01"

# G: handoff older than 14 days, unused -> ARCHIVE
note "handoffs/old-handoff.md" "title: Old Handoff
type: handoff
project: demo
status: hot
created: 2026-06-01"

# --- Event logs -------------------------------------------------------------
# A used twice (2 distinct sessions); E used once; B surfaced 9 times.
cat > "$VAULT/brain-mode/retrieval-log.jsonl" <<EOF
{"ts":"2026-07-06T10:00:00Z","session":"s1","path":"prompts/meta/promote-me.md","via":"read"}
{"ts":"2026-07-07T11:00:00Z","session":"s2","path":"prompts/meta/promote-me.md","via":"read"}
{"ts":"2026-07-07T12:00:00Z","session":"s3","path":"prompts/meta/comeback.md","via":"read"}
EOF

: > "$VAULT/brain-mode/surface-log.jsonl"
for i in $(seq 1 9); do
  printf '{"ts":"2026-07-0%sT09:00:00Z","session":"s%s","project":"demo","path":"prompts/meta/shown-unused.md"}\n' \
    "$(( (i % 7) + 1 ))" "$i" >> "$VAULT/brain-mode/surface-log.jsonl"
done

# --- Run gardener (apply, pinned clock) -------------------------------------
# Seed an OLD observation epoch so steady-state idle-decay fires. (The cold-start
# guard — fresh epoch suppresses idle archival — is tested separately below.)
printf '2025-01-01\n' > "$VAULT/brain-mode/.brain-gardener-epoch"
python3 "$GARDENER" --apply --now "$NOW" --brain "$VAULT" >/dev/null 2>&1

status_of() { grep -m1 '^status:' "$VAULT/$1" | sed 's/^status:[[:space:]]*//'; }
field_of() { grep -m1 "^$2:" "$VAULT/$1" | sed "s/^$2:[[:space:]]*//"; }

check() {  # check <desc> <actual> <expected>
  if [ "$2" = "$3" ]; then
    printf 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 ))
  else
    printf 'FAIL: %s (got "%s", expected "%s")\n' "$1" "$2" "$3"; FAIL=$(( FAIL + 1 ))
  fi
}

check "A warm+2uses -> hot (promotion)"            "$(status_of prompts/meta/promote-me.md)"  "hot"
check "B hot+9surfaced+0used -> warm (demotion)"   "$(status_of prompts/meta/shown-unused.md)" "warm"
check "C warm+200d idle -> archive"                "$(status_of prompts/meta/ancient.md)"     "archive"
check "D archive+past-window -> tombstone"         "$(status_of prompts/meta/fossil.md)"      "tombstone"
check "E archive+used -> resurrected (warm)"       "$(status_of prompts/meta/comeback.md)"    "warm"
check "F preference -> exempt, stays hot"          "$(status_of preferences/user-model.md)"   "hot"
check "G handoff idle>14d -> archive"              "$(status_of handoffs/old-handoff.md)"     "archive"

# Counter materialization
check "A use_count folded to 2"                    "$(field_of prompts/meta/promote-me.md use_count)"    "2"
check "B surface_count folded to 9"                "$(field_of prompts/meta/shown-unused.md surface_count)" "9"
check "F preference stamped decays:false"          "$(field_of preferences/user-model.md decays)"        "false"

# Idempotency: a second run must not change status counts (no double-count)
BEFORE=$(md5sum "$VAULT"/prompts/meta/*.md | md5sum)
python3 "$GARDENER" --apply --now "$NOW" --brain "$VAULT" >/dev/null 2>&1
AFTER=$(md5sum "$VAULT"/prompts/meta/*.md | md5sum)
check "idempotent second run (no churn)"           "$BEFORE" "$AFTER"

# Health report + metrics produced
check "health note written"  "$([ -f "$VAULT/daily_notes/$NOW-memory-health.md" ] && echo yes)" "yes"
check "metrics line appended" "$([ -s "$VAULT/brain-mode/metrics.jsonl" ] && echo yes)" "yes"

# --- Cold-start guard: fresh epoch must NOT archive legacy unused notes ------
COLD=$(mktemp -d)
mkdir -p "$COLD/brain-mode" "$COLD/prompts/meta"
note_cold() { printf -- '---\n%s\n---\n\nbody\n' "$2" > "$COLD/$1"; }
note_cold "prompts/meta/legacy.md" "title: Legacy
type: prompt-pattern
project: demo
status: warm
created: 2024-01-01"
# No epoch stamp exists -> first apply establishes epoch = NOW -> idle from NOW = 0.
python3 "$GARDENER" --apply --now "$NOW" --brain "$COLD" >/dev/null 2>&1
COLD_STATUS=$(grep -m1 '^status:' "$COLD/prompts/meta/legacy.md" | sed 's/^status:[[:space:]]*//')
check "cold-start: 2-year-old unused note stays warm (not archived)" "$COLD_STATUS" "warm"
check "cold-start: epoch stamp established" \
  "$([ -f "$COLD/brain-mode/.brain-gardener-epoch" ] && echo yes)" "yes"
rm -rf "$COLD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
