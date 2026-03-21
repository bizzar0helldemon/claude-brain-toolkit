---
name: brain-add-pattern
description: Add an error pattern and solution to the brain's pattern store for automatic recognition
---

## Purpose

Add a new error pattern to `$BRAIN_PATH/brain-mode/pattern-store.json`. Once added, the PostToolUseFailure hook will automatically match future errors containing the pattern key and inject the solution into your context.

## Steps

### 1. Gather pattern information

Ask the user for the following (or extract from recent conversation context if a specific error was just solved):

- **Error key** — A short, distinctive substring that appears in the error message (e.g., `"ECONNREFUSED"`, `"invalid JSON"`, `"permission denied"`, `"cannot find module"`). This is the substring the hook matches against. Shorter and more distinctive is better.
- **Solution** — The fix or workaround in plain text or markdown (1-3 sentences). This is injected into Claude's context when the error recurs.
- **Pattern ID** — A kebab-case identifier (e.g., `"econnrefused-tcp"`, `"jq-invalid-json"`). If the user does not provide one, auto-generate it from the key: lowercase, spaces → hyphens, strip special characters.

If the user invokes this command immediately after fixing an error, pre-fill the fields from conversation context and confirm with the user before writing.

### 2. Resolve the store path

```bash
STORE_PATH="$BRAIN_PATH/brain-mode/pattern-store.json"
```

### 3. Initialize the store if it does not exist

Check whether the file exists using the Read tool (attempt to read it). If it does not exist, create it using the **Write tool** with this exact content (substitute real ISO timestamps):

```json
{
  "version": "1",
  "created": "<ISO-8601 timestamp>",
  "updated": "<ISO-8601 timestamp>",
  "patterns": []
}
```

Use the Bash tool to get the current timestamp: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Do NOT call shell functions from the hooks library for initialization. Use the Write tool directly — it is more reliable at runtime than invoking shell library functions from an agent context.

### 4. Check for duplicate key

Read the current store and check whether a pattern with the same key already exists:

```bash
jq --arg key "YOUR_KEY" '.patterns[] | select(.key == $key)' "$BRAIN_PATH/brain-mode/pattern-store.json"
```

If a duplicate exists, ask the user: "A pattern with key `[key]` already exists. Update the solution, or skip?"

- If update: replace the `.solution` field for that entry and set `.updated` to now.
- If skip: confirm the skip and exit.

### 5. Add the new pattern

Get the current timestamp:

```bash
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```

Build the new pattern entry:

```json
{
  "id": "<pattern-id>",
  "key": "<error key substring>",
  "solution": "<solution text>",
  "source_file": null,
  "encounter_count": 0,
  "first_seen": "<NOW>",
  "last_seen": "<NOW>"
}
```

Write atomically using a temp file and mv:

```bash
STORE="$BRAIN_PATH/brain-mode/pattern-store.json"
TMP="${STORE}.tmp.$$"

jq \
  --arg now "$NOW" \
  --arg id "PATTERN_ID" \
  --arg key "ERROR_KEY" \
  --arg solution "SOLUTION_TEXT" \
  '.updated = $now |
   .patterns += [{
     "id": $id,
     "key": $key,
     "solution": $solution,
     "source_file": null,
     "encounter_count": 0,
     "first_seen": $now,
     "last_seen": $now
   }]' \
  "$STORE" > "$TMP" && mv "$TMP" "$STORE"
```

### 6. Confirm

Tell the user:

> "Pattern added: `[key]` — will match future errors containing this text and surface the solution automatically."

Show the full pattern entry that was written so the user can verify it looks correct.

## Notes

- Pattern keys are matched case-insensitively (the hook lowercases both sides before comparing).
- Shorter, more distinctive keys reduce false positives. Avoid generic keys like `"error"` or `"failed"`.
- The hook matches against both the error message text AND the command that failed, so keys like `"npm run build"` or `"jq -r"` also work.
- To remove a pattern later, edit `$BRAIN_PATH/brain-mode/pattern-store.json` directly with the Write/Edit tool.
