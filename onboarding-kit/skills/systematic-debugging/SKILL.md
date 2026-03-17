---
name: systematic-debugging
description: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes - four-phase framework (root cause investigation, pattern analysis, hypothesis testing, implementation) that ensures understanding before attempting solutions
---

# Systematic Debugging

## The Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST**

**ALWAYS find root cause before attempting fixes. Symptom fixes are failure.**

## When to Use This Skill

- Any bug, test failure, or unexpected behavior
- Before proposing any fix or solution
- When tempted to "just try something"

## The Four Phases

### Phase 1: Root Cause Investigation

**NO PROPOSED SOLUTIONS UNTIL PHASE 1 IS COMPLETE**

1. **Read error messages completely** - Every word matters.
2. **Reproduce the issue consistently** - If you can't reproduce it, you can't fix it.
3. **Check recent changes** - Use git history.
4. **Gather diagnostic evidence** - Add logging at component boundaries.
5. **Trace data flow** - Follow the error to its source.

### Phase 2: Pattern Analysis

1. **Find similar working code** - What equivalent functionality works?
2. **Compare against reference implementations** - Read docs completely.
3. **Identify ALL differences** - Between working and broken versions.
4. **Understand dependencies** - What assumptions does this code make?

### Phase 3: Hypothesis and Testing

1. **Form a specific, written hypothesis** - "I believe X is wrong because Y"
2. **Test with minimal changes** - Change ONE variable at a time.
3. **Verify results before proceeding**
4. **Admit knowledge gaps**

### Phase 4: Implementation

1. **Create a failing test case first**
2. **Implement a single fix** - Address root cause, not symptoms.
3. **Verify the fix works**
4. **If 3+ fixes fail** - Question the architecture.

## Red Flags (Stop and Return to Phase 1)

- "Let's just try this quick fix"
- "I don't fully understand, but this might work"
- Proposing multiple fixes at once
- Each fix reveals new problems
