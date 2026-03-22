---
phase: 11-idle-capture-offer
plan: 01
status: complete
completed: 2026-03-21
commit: 3dd2d61
---

# Plan 11-01 Summary: Idle Capture Offer

## What Was Delivered

- **hooks/lib/brain-path.sh** — Extracted `has_capturable_content()` shared function from stop.sh inline logic
- **hooks/notification-idle.sh** — New hook: guard check, content detection, additionalContext emission
- **hooks/stop.sh** — Refactored to call shared function (behavior unchanged)
- **hooks/session-start.sh** — Cleans up `.brain-idle-offered` guard file on new sessions
- **settings.json** — Notification hook registered with `idle_prompt` matcher
- **onboarding-kit/setup.sh** — Deploys notification-idle.sh + verifies registration

## Key Design Decisions

- Notification hook with `idle_prompt` matcher (native Claude Code feature, no custom timer)
- One-offer guard via `$BRAIN_PATH/.brain-idle-offered` file (env vars don't persist across hook invocations)
- Guard file written BEFORE emitting context (prevents race on rapid idle fires)
- Shared function extracted to brain-path.sh so stop.sh and notification-idle.sh use identical logic
- additionalContext suggests the offer — Claude decides tone/timing conversationally

## Verification Results

- has_capturable_content in brain-path.sh: 3 refs ✓
- has_capturable_content in stop.sh: 1 call ✓
- has_capturable_content in notification-idle.sh: 1 call ✓
- Guard file refs in notification-idle.sh: 2 (check + write) ✓
- Guard cleanup in session-start.sh: 1 ✓
- All bash files pass syntax check ✓
- settings.json Notification matcher: idle_prompt ✓
- setup.sh references: 5 ✓
- stop.sh inline TOOL_COUNT=0: 0 (removed) ✓
