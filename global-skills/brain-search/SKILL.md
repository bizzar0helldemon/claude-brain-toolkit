---
name: brain-search
description: Search the Brain vault by meaning — finds relevant notes, learnings, and patterns across all projects and sessions. Uses full-text search with optional semantic vector search.
argument-hint: <search query> [--project name] [--type type] [--limit N]
---

# Brain Search — Find Anything in Your Vault

You are searching the Brain vault for relevant knowledge using the `brain-search` CLI tool.

## Tool Location

`$BRAIN_PATH/../claude-brain-toolkit/tools/brain-search.py` — or locate via:
```bash
find "$(dirname "$BRAIN_PATH")" -name "brain-search.py" -path "*/tools/*" 2>/dev/null
```

If the tool isn't found, fall back to manual Grep-based search (see Fallback section below).

## Vault Location

The brain vault root is: `$BRAIN_PATH` (read from environment)

## Process

### Phase 1: Parse Query

Parse `$ARGUMENTS` for:
- **Search query** — the main search terms (everything that isn't a flag)
- **--project** or **-p** — filter to a specific project
- **--type** or **-t** — filter by document type (daily-note, project, pitfall, prompt-pattern, etc.)
- **--limit** or **-n** — max results (default: 10)

Examples:
- `/brain-search why did we switch to curl_cffi` — broad vault search
- `/brain-search rate limiting --project Trading-Post` — project-scoped
- `/brain-search --type pitfall authentication` — find pitfalls about auth

### Phase 2: Run Search

Run the search tool:

```bash
"$TOOLKIT_PATH/tools/brain-search" "$QUERY" --limit 10 --json
```

The wrapper script (`tools/brain-search`) automatically uses the toolkit's `.venv` if it exists (for vector search), falling back to system python3 (FTS-only mode).

If this is the first run, the tool will auto-index the vault (takes a few seconds).

Parse the JSON results. Each result contains:
- `path` — full file path
- `title` — document title
- `project` — project association
- `type` — document type
- `tags` — associated tags
- `snippet` — matched text excerpt
- `score` — relevance score

### Phase 3: Present Results

Show results grouped by relevance:

```markdown
## Search Results for "[query]"

### Top Matches

1. **[Title]** (project: X, type: Y)
   > [Snippet with key matching text]
   File: `relative/path/to/file.md`

2. **[Title]** ...

### Summary
Found [N] results across [M] projects. [Optional: brief synthesis of what the results tell us]
```

If the user's query is a question (not just keywords), **synthesize an answer** from the search results. Don't just list files — answer the question using what you found.

### Phase 4: Offer Follow-ups

After showing results, offer useful next steps:
- "Want me to read any of these in full?"
- "Should I search with different terms?"
- If results span multiple projects: "Want me to compare how [topic] is handled across projects?"

## Fallback: Grep-Based Search

If the Python tool is not available, use Grep directly:

1. Search vault for the query terms:
   ```
   Grep(pattern="term1|term2|term3", path="$BRAIN_PATH", output_mode="content", context=2)
   ```

2. Also search by filename:
   ```
   Glob(pattern="**/*keyword*.md", path="$BRAIN_PATH")
   ```

3. Parse frontmatter of matching files to build structured results.

This is less sophisticated than FTS5 (no ranking, no fuzzy matching) but still useful.

## Upgrading to Semantic Search

For true meaning-based search (not just keyword matching), the user can install:

```bash
pip install chromadb sentence-transformers
```

Then `brain-search` automatically upgrades to hybrid mode (full-text + vector search). This finds results even when the exact words don't match — e.g., searching "deployment pipeline" would find notes about "CI/CD" and "shipping to production."

## Integration Notes

- The search index lives at `$BRAIN_PATH/.brain-search.db` (auto-created)
- Index auto-updates when files change (checks mtime)
- Force reindex: `python3 tools/brain-search.py --reindex`
- View index stats: `python3 tools/brain-search.py --stats`

---

**Usage:** `/brain-search <query> [flags]`

Examples:
- `/brain-search eBay scraping patterns` — find everything about eBay scraping
- `/brain-search "why did we choose" --project Trading-Post` — project-scoped question
- `/brain-search --type pitfall` — browse all pitfalls (empty query = browse)
- `/brain-search authentication --limit 20` — more results
