# Bug: Session-start cache leaks brain context across projects

**Status:** Open
**Severity:** Medium — wrong-project context loads silently; Claude can act on the wrong vault until a human catches it
**First observed:** Multiple sessions; symptom investigated 2026-05-14
**Affected component:** `hooks/session-start.sh` (fast path) + `hooks/lib/brain-context.sh` (cache write)
**Recurrence:** Confirmed multiple times by operator before this investigation

---

## Symptom

A Claude Code session opens in project **A** (e.g. `Trading-Post-dev`), but the SessionStart hook injects brain context for project **B** (e.g. `the-cave`). The `.brain.md`, project notes, and "Brain loaded for X" banner all reference the wrong project.

If Claude doesn't notice the mismatch and the user doesn't catch it, the model can:

- Apply project-B conventions to project-A code
- Reference project-B Linear teams when filing tickets
- Treat project-A state (commits, planning files) through a project-B lens

In the 2026-05-14 instance, `/gsd-new-milestone` was about to run for Trading-Post-dev with the-cave's brain context loaded. The model caught the mismatch by reading the local `.brain.md` directly, but only because the user had a strong project frame from the conversation.

---

## Root cause

The `/clear` fast path in `hooks/session-start.sh` reuses a vault-wide cache file **without verifying the cached context belongs to the current project**.

### The cache is single-tenant per vault

```
$BRAIN_PATH/.brain-cached-context.json
```

There is exactly one cache file per vault. It stores only `{additionalContext: "..."}` — no project name, no CWD, no fingerprint of what built it. Whichever Claude Code session most recently ran the full SessionStart path "wins" the cache slot for every other session that touches the same vault.

### The fast path skips project verification

`hooks/session-start.sh` lines 25–58:

```bash
if [ "$SOURCE" = "clear" ]; then
  if [ -f "$CACHED_CONTEXT_FILE" ]; then
    CACHED_CONTEXT=$(jq -r '.additionalContext // empty' "$CACHED_CONTEXT_FILE" 2>/dev/null)
    if [ -n "$CACHED_CONTEXT" ]; then
      HOOK_OUTPUT=$(jq -n --arg ctx "$CACHED_CONTEXT" \
        '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')
      emit_json "$HOOK_OUTPUT"
      ...
      exit 0
    fi
  fi
```

Nothing in this block reads `$CWD` (which the hook receives in `HOOK_INPUT.cwd`), and nothing compares the cache origin to the current project. As long as the cache file exists and contains an `additionalContext` field, it is served verbatim.

### Sibling code path proves intent diverged from implementation

`hooks/lib/brain-context.sh` writes a separate `.brain-session-state.json` with the project name attached:

```json
{
  "project": "the-cave",
  "loaded_at": "2026-05-14T03:27:06Z",
  "entries": [...]
}
```

So the toolkit *does* know which project last ran the full path. The fast path just never consults this file.

---

## Reproduction

1. Open Claude Code in `~/Projects/writing/the-cave` and let the SessionStart hook run with `source=startup`. This writes `the-cave`'s context into `$BRAIN_PATH/.brain-cached-context.json`.
2. Close that session.
3. Open Claude Code in `~/Trading-Post-dev`. Issue a `/clear` (or trigger any session event the harness maps to `source=clear`).
4. The injected SessionStart context is `the-cave`'s, despite CWD being `Trading-Post-dev`.

In the 2026-05-14 instance, `$BRAIN_PATH/.brain-errors.log` recorded:

```
[2026-05-14T19:42:08Z] SessionStart: Fast reload from cache (source: clear)
```

…while the user was actively working in `Trading-Post-dev`. The cache file was timestamped `May 13 23:27` and `$BRAIN_PATH/.brain-session-state.json` recorded `"project": "the-cave"` — the previous evening's session.

---

## Why this is worse than it looks

1. **Silent.** The hook still emits a valid `additionalContext`, so nothing crashes. The wrong project just slides in.
2. **Survives across machines if `BRAIN_PATH` is synced** (e.g. via Dropbox/Syncthing). One machine's the-cave session can poison the cache for another machine's Trading-Post session.
3. **Triggered by routine `/clear`,** which is one of the most common commands during long sessions. Anyone who switches projects mid-day and `/clear`s is at risk.
4. **The cache TTL is effectively forever** — the file is only overwritten by a full SessionStart path, not invalidated on CWD change.

---

## Proposed fix

Two layered changes in `hooks/session-start.sh`:

### 1. Stamp the cache with the project that produced it

When the full path writes `.brain-cached-context.json` (line 140), add a `project` field:

```bash
PROJECT_NAME=$(get_project_name "$CWD" | awk '{print $1}')
jq -n \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  --arg project "$PROJECT_NAME" \
  --arg cwd "$CWD" \
  '{additionalContext: $ctx, project: $project, cwd: $cwd, cached_at: now}' \
  > "$CACHED_CONTEXT_FILE"
```

### 2. Verify project match before serving cache in the fast path

In the `source = clear` branch, refuse to serve the cache if the cached project doesn't match the current project. Fall through to the full path instead:

```bash
if [ "$SOURCE" = "clear" ]; then
  if [ -f "$CACHED_CONTEXT_FILE" ]; then
    CACHED_PROJECT=$(jq -r '.project // empty' "$CACHED_CONTEXT_FILE" 2>/dev/null)
    CURRENT_PROJECT=$(get_project_name "$CWD" | awk '{print $1}')

    if [ -n "$CACHED_PROJECT" ] && [ "$CACHED_PROJECT" != "$CURRENT_PROJECT" ]; then
      brain_log_error "SessionStart" \
        "Cache project mismatch (cached=$CACHED_PROJECT, current=$CURRENT_PROJECT) — falling through to full path"
      # Do NOT exit — let the full path run below
    else
      # Existing fast-path body
      CACHED_CONTEXT=$(jq -r '.additionalContext // empty' "$CACHED_CONTEXT_FILE" 2>/dev/null)
      if [ -n "$CACHED_CONTEXT" ]; then
        # ... emit and exit 0 as today
      fi
    fi
  fi
fi
```

Note: the fast path needs `get_project_name` available, which means `source ~/.claude/hooks/lib/brain-context.sh` must move above the fast-path block (or `get_project_name` must move to `brain-path.sh`). Currently `brain-context.sh` is only sourced after the fast path returns.

### 3. (Optional but cheap) Make the cache per-project instead of vault-wide

Replace the single cache file with `$BRAIN_PATH/.brain-cache/<project-name>.json`. Eliminates the cross-project mode entirely; no verification logic needed beyond "does the per-project file exist?". Slightly more files, but matches the mental model.

---

## Workaround until fixed

When you suspect a misload (banner says a different project than your CWD):

```bash
rm "$BRAIN_PATH/.brain-cached-context.json"
```

Then `/clear` again. The fast path falls through to "no cache yet" and serves a minimal placeholder for the current `/clear`; the next full SessionStart rebuilds the cache for the current project.

Or manually verify by reading the actual `.brain.md` in your CWD:

```bash
cat .brain.md
```

The local file is always authoritative for project identity, regardless of what the hook injected.

---

## Test cases to add

When the fix lands, add a regression test under `hooks/tests/`:

1. **Cache hit, same project** — startup in project A writes cache; `/clear` in project A serves cached A context.
2. **Cache miss, different project** — startup in project A writes cache; `/clear` in project B falls through to full path and serves project-B context.
3. **No cache, /clear** — preserves current minimal-context behavior.
4. **Empty `.brain-cached-context.json`** — graceful fall-through, no error.
5. **Cache file with no `project` field (legacy)** — fall through to full path (treat as untrusted).

---

## Linear

The toolkit Linear team is **Brain Toolkit** (ID `6a53841e-31fa-4a8d-b3c8-132d80f8e16c`). When ready, file this as a `Bug` (severity medium) with this doc linked.

Suggested title: `Session-start /clear fast path leaks brain context across projects`

---

## Pointers (for the next session that resumes this)

- Hook entrypoint: `hooks/session-start.sh:25-58` (fast path)
- Cache write: `hooks/session-start.sh:140`
- Project-name resolver: `hooks/lib/brain-context.sh:108-147` (`get_project_name`)
- Cache file location: `$BRAIN_PATH/.brain-cached-context.json`
- Session state with project (currently unused by fast path): `$BRAIN_PATH/.brain-session-state.json`
- Error log to verify the symptom in the wild: `$BRAIN_PATH/.brain-errors.log` — grep for `SessionStart: Fast reload from cache`
