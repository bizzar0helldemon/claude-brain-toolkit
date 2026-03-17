---
name: simplification-cascades
description: Find one insight that eliminates multiple components - "if this is true, we don't need X, Y, or Z"
---

# Simplification Cascades

## Overview

Sometimes one insight eliminates 10 things. Look for the unifying principle that makes multiple components unnecessary.

**Core principle:** "Everything is a special case of..." collapses complexity dramatically.

## Quick Reference

| Symptom | Likely Cascade |
|---------|----------------|
| Same thing implemented 5+ ways | Abstract the common pattern |
| Growing special case list | Find the general case |
| Complex rules with exceptions | Find the rule that has no exceptions |
| Excessive config options | Find defaults that work for 95% |

## The Pattern

**Look for:**
- Multiple implementations of similar concepts
- Special case handling everywhere
- Complex rules with many exceptions

**Ask:** "What if they're all the same thing underneath?"

## Process

1. **List the variations** - What's implemented multiple ways?
2. **Find the essence** - What's the same underneath?
3. **Extract abstraction** - What's the domain-independent pattern?
4. **Test it** - Do all cases fit cleanly?
5. **Measure cascade** - How many things become unnecessary?

## Remember

- Simplification cascades = 10x wins, not 10% improvements
- One powerful abstraction > ten clever hacks
- Measure in "how many things can we delete?"
