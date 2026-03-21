# Phase 9: Error Pattern Intelligence - Research

**Researched:** 2026-03-21
**Domain:** Shell hooks, JSON pattern store, adaptive response logic, soft-cap pruning
**Confidence:** HIGH (all components extend verified Phase 4 infrastructure; no new dependencies required)

---

## Summary

Phase 9 extends the existing error pattern recognition system (Phase 4) in two directions: (1) verified encounter count tracking with a soft-cap pruning strategy to prevent unbounded store growth, and (2) encounter-count-aware response adaptation in the hook output and the brain-mode agent.

The good news is that the baseline infrastructure is already correct. Phase 4 already increments `encounter_count` atomically on every match via `update_encounter_count` in `hooks/lib/brain-path.sh`. The `encounter_count` field exists in every pattern entry and is updated correctly. What Phase 9 adds is: (a) confirming the count is inspectable (MENT-01 verification requirement), (b) adding a prune function that enforces a soft cap, and (c) passing the encounter count from the hook to the agent so it can modulate its response (MENT-02).

The critical design question is where adaptation happens. The PostToolUseFailure hook injects context into Claude's input stream via `additionalContext`. It knows the encounter count at match time. The right approach is to include the encounter count (and the threshold tier) inside `additionalContext` so the brain-mode agent receives both the solution and its recurrence tier. The agent then decides how to respond based on the tier — full explanation at tier 1, brief reminder at tier 2-4, root cause flag at tier 5+. No new hook events are needed; the adaptation is entirely in the text injected by the hook and the agent instructions that interpret it.

**Primary recommendation:** Extend `post-tool-use-failure.sh` to include encounter count and tier label in `additionalContext`. Add prune logic to `update_encounter_count` (or a new `prune_pattern_store` function). Update `agents/brain-mode.md` with tier-response instructions. No new dependencies, no new hook registrations.

---

## Standard Stack

### Core

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| `hooks/lib/brain-path.sh` | Existing (Phase 4) | `update_encounter_count`, `init_pattern_store`, `emit_json` | Already provides atomic pattern store writes; Phase 9 extends it with prune logic |
| `hooks/post-tool-use-failure.sh` | Existing (Phase 4) | Error matching, `additionalContext` injection | Already wired; Phase 9 adds tier calculation and count injection |
| `$BRAIN_PATH/brain-mode/pattern-store.json` | Existing (Phase 4) | Persists patterns with `encounter_count` | Already increments correctly; Phase 9 adds `soft_cap` metadata |
| `jq` 1.6+ | Hard dep since Phase 1 | Sort by encounter count for prune, read count at match time | Already used everywhere; `sort_by`, `limit`, `reverse` are standard jq |
| `agents/brain-mode.md` | Existing (Phase 4) | Error Pattern Recognition section | Phase 9 adds tier-response behavior instructions |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `sort_by(.encounter_count)` in jq | jq 1.6+ | Identify least-used patterns for pruning | Used in prune function to select which patterns to remove |
| `limit(N; .patterns[] \| select(...))` | jq 1.6+ | Pick top-N patterns to keep | Used in prune to retain high-use patterns when cap is exceeded |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Passing tier via `additionalContext` text | Separate hook output field (e.g., `encounterTier`) | `additionalContext` is the only consumer-visible field in PostToolUseFailure output. No custom fields are exposed to the agent beyond this. Use `additionalContext` and include tier label in the text. |
| Pruning in `update_encounter_count` | Standalone `prune_pattern_store` function | Both are valid. Pruning after an increment means the store size is checked on every match event — low overhead, always consistent. A standalone function would need to be called separately. Integrate into `update_encounter_count` to keep behavior in one place. |
| Soft cap via entry count | Soft cap via total byte size | Entry count is simple to implement and inspect. Byte size requires `wc -c` or `jq length` on the file. Entry count is sufficient at this scale (tens of patterns). |
| Threshold at 5 for root cause flag | Configurable threshold | Hardcoded thresholds for now — MENT-03 (full adaptive mentoring with tuned thresholds) is a future requirement. Phase 9 uses fixed tiers: 1 = full, 2-4 = brief, 5+ = root cause. |

**Installation:**

```bash
# No new dependencies. All changes are to existing files.
```

---

## Architecture Patterns

### Recommended File Changes for Phase 9

```
hooks/
├── lib/
│   └── brain-path.sh          # EXTEND — add prune_pattern_store, modify update_encounter_count
└── post-tool-use-failure.sh   # EXTEND — read count after update, calculate tier, inject tier in additionalContext

agents/
└── brain-mode.md              # EXTEND — add tier-response instructions in Error Pattern Recognition section

$BRAIN_PATH/brain-mode/
└── pattern-store.json         # EXTEND — add "soft_cap" top-level field (optional, with default fallback)
```

No new files. No new hook registrations. No settings.json changes.

### Pattern 1: Tier Calculation in the Hook

**What:** After `update_encounter_count` runs, the hook reads back the updated encounter count for the matched pattern and calculates which tier it falls into. The tier label is included in `additionalContext`.

**When to use:** On every PostToolUseFailure match.

**Example:**

```bash
# After update_encounter_count runs, read the updated count
COUNT=$(jq -r \
  --arg err "$ERROR_MSG" \
  '.patterns[] | . as $p | select(($err | ascii_downcase) | contains($p.key | ascii_downcase)) | .encounter_count' \
  "$PATTERN_STORE" 2>/dev/null | head -1)

# Determine tier
if [ "$COUNT" -ge 5 ] 2>/dev/null; then
  TIER="root-cause-flag"
  TIER_INSTRUCTION="[Encounter $COUNT — flag for root cause investigation, not repeated solution]"
elif [ "$COUNT" -ge 2 ] 2>/dev/null; then
  TIER="brief-reminder"
  TIER_INSTRUCTION="[Encounter $COUNT — give brief reminder only, not full explanation]"
else
  TIER="full-explanation"
  TIER_INSTRUCTION="[Encounter $COUNT — give full explanation and solution steps]"
fi

CONTEXT_MSG="Past solution found for this error [encounter_count=$COUNT tier=$TIER]:\n\n$MATCH\n\n$TIER_INSTRUCTION"
emit_json "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUseFailure\",\"additionalContext\":\"$CONTEXT_MSG\"}}"
```

**Critical:** The integer comparison `[ "$COUNT" -ge 5 ]` will silently fail or behave unexpectedly if `$COUNT` is empty (no match in jq output) or non-numeric. Guard with a default:

```bash
COUNT="${COUNT:-0}"
# Validate it is numeric
if ! printf '%s' "$COUNT" | grep -qE '^[0-9]+$'; then
  COUNT=0
fi
```

### Pattern 2: Soft-Cap Pruning in brain-path.sh

**What:** After incrementing encounter count, check if the total number of patterns exceeds a soft cap (default: 50). If it does, remove the N least-used patterns (lowest `encounter_count`) until the store is back at the cap.

**When to use:** Called at the end of `update_encounter_count`.

**Example:**

```bash
prune_pattern_store() {
  local store_path="$1"
  local cap="${2:-50}"  # default soft cap = 50

  local count
  count=$(jq '.patterns | length' "$store_path" 2>/dev/null)

  if [ -z "$count" ] || [ "$count" -le "$cap" ]; then
    return 0
  fi

  local tmp_file
  tmp_file="${store_path}.tmp.$$"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Keep the top-$cap patterns by encounter_count (highest first)
  if ! jq \
    --argjson cap "$cap" \
    --arg now "$now" \
    '.updated = $now |
     .patterns = [ .patterns | sort_by(.encounter_count) | reverse | .[:$cap][] ]' \
    "$store_path" > "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file" 2>/dev/null
    brain_log_error "PatternStore" "prune failed for store at $store_path"
    return 0
  fi

  if ! mv "$tmp_file" "$store_path" 2>/dev/null; then
    rm -f "$tmp_file" 2>/dev/null
    brain_log_error "PatternStore" "prune atomic write failed for store at $store_path"
  fi

  return 0
}
```

**Calling convention:** Add `prune_pattern_store "$store_path"` at the end of `update_encounter_count`, after the mv.

### Pattern 3: Tier-Response Instructions in brain-mode.md

**What:** The agent receives tier metadata in `additionalContext`. The Error Pattern Recognition section of `agents/brain-mode.md` needs explicit instructions for how to respond at each tier.

**When to use:** Any time `additionalContext` includes `tier=` metadata.

**Example addition to brain-mode.md:**

```markdown
## Error Pattern Recognition

When a Bash command fails, the PostToolUseFailure hook checks the error against stored patterns.
If a match is found, the hook injects the past solution AND a tier instruction into your context.
Respond according to the tier:

- **tier=full-explanation** (encounter 1): Show the full past solution with all steps. Make it prominent.
- **tier=brief-reminder** (encounters 2-4): Give a 1-2 sentence reminder: "You've seen this before — [key fix]."
- **tier=root-cause-flag** (encounters 5+): Do not repeat the solution. Instead say: "This error has recurred [N] times. The recurring pattern suggests a root cause that hasn't been addressed. Let's investigate why this keeps happening rather than applying the fix again."
```

### Anti-Patterns to Avoid

- **Reading encounter_count before update:** The count from before the increment would be one less than reality. Always read count AFTER `update_encounter_count` completes.
- **Hard-coding the pattern-store path in prune logic:** Use `$BRAIN_PATH/brain-mode/pattern-store.json` via the existing variable convention. Never hardcode paths.
- **Integer comparison without numeric guard:** `[ "$COUNT" -ge 5 ]` will produce a bash error if COUNT is empty or non-numeric. Always guard.
- **Pruning by last_seen instead of encounter_count:** Recency-based pruning would discard valuable patterns that haven't recurred recently but have high historical counts. Prune by lowest `encounter_count` (least-used patterns go first).
- **Exposing prune output to Claude:** Pruning is a housekeeping operation. Never surface it in `additionalContext`. Log to `.brain-errors.log` if pruning occurred (for debugging), but don't inject prune notifications into the session.
- **Running prune on every PostToolUseFailure call (even non-matches):** Only prune after a successful match + increment. Non-matching hook calls should not incur the jq overhead of counting patterns. Guard prune behind the `if [ -n "$MATCH" ]` branch.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Least-recently-used eviction | Custom LRU cache | `sort_by(.encounter_count) \| reverse \| .[:N]` in jq | jq's sort is sufficient for tens of patterns. LRU requires tracking access timestamps as a secondary sort key — unnecessary complexity. |
| Tier thresholds in a config file | `tier-thresholds.json` or env vars | Hardcoded constants in the shell script | MENT-03 (configurable thresholds) is explicitly deferred to a future requirement. Phase 9 uses fixed values. Adding a config file now is premature. |
| Encounter count persistence across reboots | Separate database or log file | Existing `encounter_count` field in `pattern-store.json` | Already persists. The field survives session resets and reboots. No additional persistence layer needed. |
| Tier display formatting | Custom formatting library | Plain text label in `additionalContext` string | Claude interprets plain text instructions reliably. Markdown or JSON tier metadata are over-engineering at this scale. |

**Key insight:** Phase 9 is two focused additions to existing files: a prune function in `brain-path.sh` and tier metadata in `additionalContext`. The Phase 4 infrastructure handles everything else.

---

## Common Pitfalls

### Pitfall 1: Reading Encounter Count Before Incrementing

**What goes wrong:** The hook reads `encounter_count` from `pattern-store.json` before calling `update_encounter_count`. The count is one behind reality — a pattern on its 5th encounter shows as count 4, so it gets tier=brief-reminder instead of tier=root-cause-flag.

**Why it happens:** Natural code ordering — match first, read count, then update. But the requirement says "on encounter 5+" so the count should reflect the new increment.

**How to avoid:** Call `update_encounter_count` first. Then read the count back from the (now-updated) store. The read-after-write ensures the count used for tier calculation is correct.

**Warning signs:** The root-cause-flag tier never triggers, or triggers one encounter later than expected.

---

### Pitfall 2: Non-Numeric COUNT from jq

**What goes wrong:** If no pattern matches in the jq query for the count read-back, `$COUNT` is empty. The bash integer comparison `[ "" -ge 5 ]` produces `bash: [: : integer expression expected` and may default to tier=full-explanation on all encounters.

**Why it happens:** The jq query pipes through `head -1` and returns empty string when no rows match, which can happen if the pattern store was modified between the match step and the count read-back (race condition, or if the match used the error message but the count read-back re-derives from the same match logic after pruning removed the pattern).

**How to avoid:** Default COUNT to 0 if empty or non-numeric. Add a numeric guard before integer comparison. Use `"${COUNT:-0}"` and validate with `grep -qE '^[0-9]+$'`.

**Warning signs:** Unexpected tier=full-explanation on encounters where you expected tier=brief-reminder.

---

### Pitfall 3: Shell JSON Injection in additionalContext

**What goes wrong:** The solution text injected into `additionalContext` contains double quotes, backslashes, or literal newlines. The hand-assembled JSON string breaks. `emit_json` detects invalid JSON and suppresses the output entirely — the user sees no past solution at all.

**Why it happens:** The current `post-tool-use-failure.sh` uses string interpolation: `"{\"hookSpecificOutput\":...,\"additionalContext\":\"$CONTEXT_MSG\"}"`. This is fragile. Special characters in `$MATCH` or `$TIER_INSTRUCTION` break the JSON.

**How to avoid:** Use `jq --arg` to construct the JSON safely. Never interpolate solution text directly into a JSON string literal:

```bash
CONTEXT_MSG="Past solution found [encounter_count=$COUNT tier=$TIER]:\n\n$MATCH\n\n$TIER_INSTRUCTION"
OUTPUT=$(jq -n \
  --arg ctx "$CONTEXT_MSG" \
  '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":$ctx}}')
emit_json "$OUTPUT"
```

**This also fixes the existing warning from Phase 4 verification** (line 46-47 anti-pattern noted in 04-VERIFICATION.md). Phase 9 is a natural opportunity to close this known gap.

**Warning signs:** Solutions with quotes ("Use `jq --arg`") never surface to the agent.

---

### Pitfall 4: Prune Discards High-Value Patterns

**What goes wrong:** A pattern with high encounter_count is removed by prune because `sort_by(.encounter_count)` sorts ascending and the slicing takes `[:N]` (first N = lowest counts). If the jq expression is `sort_by(.encounter_count) | .[:N]` instead of `sort_by(.encounter_count) | reverse | .[:N]`, the highest-use patterns are removed.

**Why it happens:** Confusion about sort direction. `sort_by` in jq is ascending by default.

**How to avoid:** Always use `sort_by(.encounter_count) | reverse | .[:N]` — reverse after sort to get descending (highest first), then take `[:N]` to keep the top N.

**Verification:** After prune, check that the remaining patterns have the highest encounter counts in the pre-prune store.

---

### Pitfall 5: MENT-01 "Verified Incrementing" Requirement

**What goes wrong:** The plan treats MENT-01 as purely a coding task. But the requirement says "encounter_count is **verified** incrementing." This implies a verification test is needed in the plan, not just correct code.

**Why it happens:** The code already increments counts (Phase 4). MENT-01 is specifically asking for a verification artifact — an inspectable proof that it works.

**How to avoid:** The PLAN for Phase 9 should include an explicit verification task: use `jq '.patterns[] | {key, encounter_count}'` to inspect the store before and after a triggered match, showing the count increased. This is the "verifiable by inspecting the store file" component of success criterion 1.

---

## Code Examples

Verified patterns from Phase 4 infrastructure (directly extended in Phase 9):

### Tier Calculation with Numeric Guard

```bash
# Source: Project convention — extending post-tool-use-failure.sh pattern from Phase 4

# Read count after update (update_encounter_count already ran)
COUNT=$(jq -r \
  --arg err "$ERROR_MSG" \
  '.patterns[] | . as $p | select(($err | ascii_downcase) | contains($p.key | ascii_downcase)) | .encounter_count' \
  "$PATTERN_STORE" 2>/dev/null | head -1)

# Guard: default to 0 if empty or non-numeric
COUNT="${COUNT:-0}"
if ! printf '%s' "$COUNT" | grep -qE '^[0-9]+$'; then
  COUNT=0
fi

# Tier thresholds (fixed for Phase 9 — configurable in future MENT-03)
if [ "$COUNT" -ge 5 ]; then
  TIER="root-cause-flag"
  TIER_NOTE="[Encounter $COUNT — investigate root cause, do not repeat the solution]"
elif [ "$COUNT" -ge 2 ]; then
  TIER="brief-reminder"
  TIER_NOTE="[Encounter $COUNT — give a 1-2 sentence reminder only]"
else
  TIER="full-explanation"
  TIER_NOTE="[Encounter $COUNT — give full explanation with steps]"
fi
```

### Safe JSON Construction via jq --arg

```bash
# Source: jq documentation — --arg passes shell variables safely (handles quotes, backslashes)
# Fixes the existing Phase 4 warning about unescaped solution text in additionalContext

CONTEXT_MSG=$(printf "Past solution found [encounter_count=%s tier=%s]:\n\n%s\n\n%s" \
  "$COUNT" "$TIER" "$MATCH" "$TIER_NOTE")

OUTPUT=$(jq -n \
  --arg ctx "$CONTEXT_MSG" \
  '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":$ctx}}')

emit_json "$OUTPUT"
```

### Prune Function (jq sort + reverse + slice)

```bash
# Source: jq documentation — sort_by, reverse, slice operator
# Keep top-N by encounter_count; discard lowest

jq \
  --argjson cap "$cap" \
  --arg now "$now" \
  '.updated = $now |
   .patterns = [ .patterns | sort_by(.encounter_count) | reverse | .[:$cap][] ]' \
  "$store_path" > "$tmp_file"
```

### Verification Command (for PLAN verification task)

```bash
# Inspect encounter counts before and after a triggered error match
# Run before triggering a known error:
jq '.patterns[] | {key, encounter_count}' "$BRAIN_PATH/brain-mode/pattern-store.json"

# Trigger the error. Then run again:
jq '.patterns[] | {key, encounter_count}' "$BRAIN_PATH/brain-mode/pattern-store.json"

# Diff should show the matched pattern's encounter_count incremented by 1.
```

---

## State of the Art

| Old Approach (Phase 4) | New Approach (Phase 9) | Impact |
|------------------------|------------------------|--------|
| `additionalContext` injects solution only | `additionalContext` injects solution + encounter_count + tier label | Agent can now modulate response based on recurrence |
| `update_encounter_count` updates but doesn't prune | `update_encounter_count` + `prune_pattern_store` | Store stays bounded at soft cap |
| JSON built via string interpolation (fragile) | JSON built via `jq --arg` (safe) | Fixes existing Phase 4 warning; handles solutions with quotes |
| Agent always gives full explanation | Agent uses tier to vary verbosity | Reduces repetitive solution noise for persistent errors |

**Known gap being closed:** Phase 4 verification (04-VERIFICATION.md) logged a warning at lines 46-47 of `post-tool-use-failure.sh`: "Shell-interpolated `$MATCH` into manual JSON string — if solution text contains double quotes, JSON will be malformed." Phase 9 closes this by migrating to `jq --arg` construction.

---

## Open Questions

1. **What is the right soft cap value?**
   - What we know: No usage data exists yet. The requirements don't specify a number.
   - What's unclear: Too low (10-20) and legitimate patterns get evicted before they accumulate enough counts to be useful. Too high (500) and the store grows unwieldy.
   - Recommendation: Default to 50. This is large enough to cover real-world usage comfortably and small enough to stay fast with jq. Document the cap as a constant in `brain-path.sh` so it's easy to change. `prune_pattern_store` accepts the cap as a parameter with a default.

2. **Should the soft cap be configurable in pattern-store.json?**
   - What we know: Adding `"soft_cap": 50` to the store JSON allows per-vault configuration without code changes.
   - What's unclear: Is this complexity worth it for Phase 9? MENT-03 (extended adaptive mentoring) is deferred.
   - Recommendation: Keep it simple for Phase 9. Hardcode the default in the function. If the user wants to change it, they edit `brain-path.sh` or the store JSON. Don't add a config field in Phase 9.

3. **Should tier thresholds be the same for all patterns?**
   - What we know: The requirements specify fixed tiers: 1 = full, 2-4 = brief, 5+ = root cause.
   - What's unclear: Some errors might warrant root-cause investigation sooner (e.g., security errors) vs. later (e.g., minor typos).
   - Recommendation: Fixed thresholds for Phase 9 as specified. Per-pattern thresholds are MENT-03 territory.

4. **Does the PLAN need to address the existing JSON injection bug simultaneously?**
   - What we know: Phase 4 VERIFICATION flagged the `$MATCH` interpolation issue as a warning (not a blocker). Phase 9 extends the same code path.
   - Recommendation: Yes, fix the JSON construction during Phase 9 plan execution. It's the same line, the fix is the same (`jq --arg`), and leaving it would be an obvious tech debt accumulation. Include it as part of the Phase 9 plan task.

---

## Sources

### Primary (HIGH confidence)

- `hooks/post-tool-use-failure.sh` (project) — lines 30-54, current Phase 4 implementation; basis for Phase 9 extension
- `hooks/lib/brain-path.sh` (project) — lines 178-214, `update_encounter_count`; Phase 9 extends this function
- `.planning/phases/04-intelligence-layer/04-VERIFICATION.md` (project) — Phase 4 warning at lines 46-47 about JSON injection; explicitly flagged for fix
- `.planning/phases/04-intelligence-layer/04-02-SUMMARY.md` (project) — confirmed patterns: `. as $p` jq binding, atomic write, Write-tool initialization convention
- `.planning/REQUIREMENTS.md` (project) — MENT-01, MENT-02 requirements; MENT-03 deferred

### Secondary (MEDIUM confidence)

- jq 1.6 documentation — `sort_by`, `reverse`, `limit`, slice operator `.[N:M]`, `--argjson` flag — standard jq features used for prune implementation
- Claude Code Hooks reference — `additionalContext` in PostToolUseFailure output; confirmed Bash tool failure context injection is reliable (verified in Phase 4)

### Tertiary (LOW confidence)

- None. All components are direct extensions of verified Phase 4 artifacts.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all files exist and are verified Phase 4 artifacts; no new dependencies
- Architecture: HIGH — tier calculation, prune function, and agent instruction patterns are derived directly from existing code; jq operations are well-understood
- Pitfalls: HIGH — pitfalls 1-4 are grounded in the existing codebase; pitfall 5 is derived from requirements analysis

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (30 days — stack is stable internal tooling)
