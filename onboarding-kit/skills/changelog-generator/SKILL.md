---
name: changelog-generator
description: Transforms technical git commits into polished, user-friendly changelogs that customers and users will understand and appreciate
---

# Changelog Generator Skill

## When to Use This Skill

- Preparing release notes for a new version
- Creating weekly or monthly product update summaries
- Documenting changes for customers
- Writing changelog entries for app store submissions
- Generating update notifications
- Maintaining a public changelog/product updates page

## What This Skill Does

1. **Scans Git History**: Analyzes commits from a specific time period or between versions
2. **Categorizes Changes**: Groups commits into logical categories (features, improvements, bug fixes, breaking changes, security)
3. **Translates Technical to User-Friendly**: Converts developer commits into customer language
4. **Formats Professionally**: Creates clean, structured changelog entries
5. **Filters Noise**: Excludes internal commits (refactoring, tests, etc.)

## How to Use

- "Create a changelog from commits since last release"
- "Generate changelog for all commits from the past week"
- "Create release notes for version 2.5.0"
- "Create a changelog for all commits between March 1 and March 15"

## Tips

- Run from your git repository root
- Specify date ranges for focused changelogs
- Review and adjust the generated changelog before publishing
- Save output directly to CHANGELOG.md
