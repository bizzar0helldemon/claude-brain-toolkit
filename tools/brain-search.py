#!/usr/bin/env python3
"""
brain-search — Semantic search over a Brain vault.

Indexes all .md files in $BRAIN_PATH into SQLite FTS5 for full-text search.
Optionally upgrades to vector search when sentence-transformers + chromadb are
available (pip install sentence-transformers chromadb).

Usage:
    brain-search "why did we switch to GraphQL"
    brain-search "eBay rate limiting" --limit 10
    brain-search --reindex                        # force rebuild
    brain-search --stats                          # index health
    brain-search "auth decisions" --wing myproject
    brain-search "error pattern" --type pitfall

The index lives at $BRAIN_PATH/.brain-search.db (SQLite) and
$BRAIN_PATH/.brain-search-vectors/ (ChromaDB, optional).
"""

import argparse
import hashlib
import os
import re
import sqlite3
import sys
import textwrap
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BRAIN_PATH = os.environ.get("BRAIN_PATH", "")
SKIP_DIRS = {".git", ".claude", "node_modules", "__pycache__", ".obsidian"}
SKIP_FILES = {".brain-session-state.json", ".brain-errors.log", ".brain-cached-context.json"}

# ---------------------------------------------------------------------------
# Frontmatter parser (pure-Python, no pyyaml needed)
# ---------------------------------------------------------------------------

def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Extract YAML frontmatter and body from markdown text."""
    meta = {}
    body = text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            body = parts[2].strip()
            for line in parts[1].strip().splitlines():
                if ":" in line:
                    key, _, val = line.partition(":")
                    key = key.strip()
                    val = val.strip().strip('"').strip("'")
                    # Handle YAML arrays: [a, b, c]
                    if val.startswith("[") and val.endswith("]"):
                        val = [v.strip().strip('"').strip("'") for v in val[1:-1].split(",")]
                    meta[key] = val
    return meta, body


def file_hash(path: Path) -> str:
    """Fast content hash for change detection."""
    h = hashlib.md5()
    h.update(str(path.stat().st_mtime_ns).encode())
    h.update(str(path.stat().st_size).encode())
    return h.hexdigest()

# ---------------------------------------------------------------------------
# SQLite FTS5 index (zero dependencies)
# ---------------------------------------------------------------------------

class FTSIndex:
    """Full-text search index backed by SQLite FTS5."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self._ensure_schema()

    def _ensure_schema(self):
        self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS docs (
                path TEXT PRIMARY KEY,
                hash TEXT NOT NULL,
                title TEXT,
                project TEXT,
                type TEXT,
                tags TEXT,
                mtime REAL,
                indexed_at REAL
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
                path, title, body, project, type, tags,
                content='',
                tokenize='porter unicode61'
            );
        """)
        self.conn.commit()

    def needs_update(self, path: str, content_hash: str) -> bool:
        row = self.conn.execute(
            "SELECT hash FROM docs WHERE path = ?", (path,)
        ).fetchone()
        return row is None or row[0] != content_hash

    def upsert(self, path: str, content_hash: str, title: str, body: str,
               project: str, doc_type: str, tags: str, mtime: float):
        # Remove old FTS entry if exists
        rowid = self.conn.execute(
            "SELECT rowid FROM docs WHERE path = ?", (path,)
        ).fetchone()
        if rowid:
            self.conn.execute(
                "INSERT INTO docs_fts(docs_fts, rowid, path, title, body, project, type, tags) "
                "VALUES('delete', ?, ?, ?, ?, ?, ?, ?)",
                (rowid[0], path, "", "", "", "", "")
            )

        # Upsert metadata
        self.conn.execute("""
            INSERT INTO docs(path, hash, title, project, type, tags, mtime, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                hash=excluded.hash, title=excluded.title, project=excluded.project,
                type=excluded.type, tags=excluded.tags, mtime=excluded.mtime,
                indexed_at=excluded.indexed_at
        """, (path, content_hash, title, project, doc_type, tags, mtime, time.time()))

        # Get the rowid for FTS
        rowid = self.conn.execute(
            "SELECT rowid FROM docs WHERE path = ?", (path,)
        ).fetchone()[0]

        # Insert FTS entry
        self.conn.execute(
            "INSERT INTO docs_fts(rowid, path, title, body, project, type, tags) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (rowid, path, title, body, project, doc_type, tags)
        )

    def remove(self, path: str):
        rowid = self.conn.execute(
            "SELECT rowid FROM docs WHERE path = ?", (path,)
        ).fetchone()
        if rowid:
            self.conn.execute(
                "INSERT INTO docs_fts(docs_fts, rowid, path, title, body, project, type, tags) "
                "VALUES('delete', ?, ?, ?, ?, ?, ?, ?)",
                (rowid[0], path, "", "", "", "", "")
            )
            self.conn.execute("DELETE FROM docs WHERE path = ?", (path,))

    def search(self, query: str, limit: int = 5, project: str = None,
               doc_type: str = None) -> list[dict]:
        """Search using FTS5 with BM25 ranking."""
        # Escape special FTS5 characters in query
        safe_query = re.sub(r'[^\w\s]', ' ', query).strip()
        if not safe_query:
            return []

        # Build FTS5 query — individual terms joined with OR for broad matching
        # Each term searches across all columns
        terms = safe_query.split()
        fts_query = " OR ".join(terms)

        sql = """
            SELECT d.path, d.title, d.project, d.type, d.tags, d.mtime,
                   snippet(docs_fts, 2, '>>>', '<<<', '...', 48) as snippet,
                   rank
            FROM docs_fts
            JOIN docs d ON docs_fts.rowid = d.rowid
            WHERE docs_fts MATCH ?
        """
        params = [fts_query]

        if project:
            sql += " AND d.project LIKE ?"
            params.append(f"%{project}%")
        if doc_type:
            sql += " AND d.type = ?"
            params.append(doc_type)

        sql += " ORDER BY rank LIMIT ?"
        params.append(limit)

        try:
            rows = self.conn.execute(sql, params).fetchall()
        except sqlite3.OperationalError:
            # Fallback: try each term individually
            rows = []
            for term in terms:
                try:
                    rows += self.conn.execute(
                        """SELECT d.path, d.title, d.project, d.type, d.tags, d.mtime,
                                  snippet(docs_fts, 2, '>>>', '<<<', '...', 48) as snippet,
                                  rank
                           FROM docs_fts
                           JOIN docs d ON docs_fts.rowid = d.rowid
                           WHERE docs_fts MATCH ?
                           ORDER BY rank LIMIT ?""",
                        (term, limit)
                    ).fetchall()
                except sqlite3.OperationalError:
                    continue

        results = []
        for row in rows:
            results.append({
                "path": row[0],
                "title": row[1] or os.path.basename(row[0]),
                "project": row[2] or "",
                "type": row[3] or "",
                "tags": row[4] or "",
                "mtime": row[5],
                "snippet": row[6] or "",
                "score": abs(row[7]) if row[7] else 0,
            })
        return results

    def stats(self) -> dict:
        total = self.conn.execute("SELECT COUNT(*) FROM docs").fetchone()[0]
        by_type = self.conn.execute(
            "SELECT type, COUNT(*) FROM docs GROUP BY type ORDER BY COUNT(*) DESC"
        ).fetchall()
        by_project = self.conn.execute(
            "SELECT project, COUNT(*) FROM docs WHERE project != '' GROUP BY project ORDER BY COUNT(*) DESC LIMIT 10"
        ).fetchall()
        oldest = self.conn.execute(
            "SELECT MIN(indexed_at) FROM docs"
        ).fetchone()[0]
        newest = self.conn.execute(
            "SELECT MAX(indexed_at) FROM docs"
        ).fetchone()[0]
        return {
            "total": total,
            "by_type": by_type,
            "by_project": by_project,
            "oldest_index": oldest,
            "newest_index": newest,
        }

    def all_paths(self) -> set[str]:
        return {row[0] for row in self.conn.execute("SELECT path FROM docs").fetchall()}

    def commit(self):
        self.conn.commit()

    def close(self):
        self.conn.close()

# ---------------------------------------------------------------------------
# Optional: ChromaDB vector search (requires pip install chromadb sentence-transformers)
# ---------------------------------------------------------------------------

_VECTOR_AVAILABLE = False

def _try_import_vector():
    global _VECTOR_AVAILABLE
    try:
        import chromadb  # noqa: F401
        _VECTOR_AVAILABLE = True
    except ImportError:
        _VECTOR_AVAILABLE = False
    return _VECTOR_AVAILABLE


class VectorIndex:
    """Semantic vector search backed by ChromaDB + sentence-transformers."""

    def __init__(self, persist_dir: str):
        import chromadb
        self.client = chromadb.PersistentClient(path=persist_dir)
        self.collection = self.client.get_or_create_collection(
            name="brain_vault",
            metadata={"hnsw:space": "cosine"}
        )

    def upsert(self, doc_id: str, text: str, metadata: dict):
        # Chunk long documents (ChromaDB has limits)
        max_chars = 8000
        chunks = [text[i:i+max_chars] for i in range(0, len(text), max_chars)]
        for i, chunk in enumerate(chunks):
            chunk_id = f"{doc_id}::chunk{i}" if i > 0 else doc_id
            self.collection.upsert(
                ids=[chunk_id],
                documents=[chunk],
                metadatas=[metadata]
            )

    def remove(self, doc_id: str):
        try:
            # Remove main doc and any chunks
            existing = self.collection.get(where={"path": doc_id})
            if existing and existing["ids"]:
                self.collection.delete(ids=existing["ids"])
        except Exception:
            try:
                self.collection.delete(ids=[doc_id])
            except Exception:
                pass

    def search(self, query: str, limit: int = 5, where: dict = None) -> list[dict]:
        kwargs = {"query_texts": [query], "n_results": limit}
        if where:
            kwargs["where"] = where
        results = self.collection.query(**kwargs)

        out = []
        if results and results["documents"]:
            for i, doc in enumerate(results["documents"][0]):
                meta = results["metadatas"][0][i] if results["metadatas"] else {}
                dist = results["distances"][0][i] if results["distances"] else 0
                out.append({
                    "path": meta.get("path", ""),
                    "title": meta.get("title", ""),
                    "project": meta.get("project", ""),
                    "type": meta.get("type", ""),
                    "tags": meta.get("tags", ""),
                    "snippet": doc[:200] + "..." if len(doc) > 200 else doc,
                    "score": 1 - dist,  # cosine similarity
                })
        return out

    def count(self) -> int:
        return self.collection.count()

# ---------------------------------------------------------------------------
# Indexer
# ---------------------------------------------------------------------------

def collect_vault_files(vault_path: Path) -> list[Path]:
    """Walk vault and collect indexable .md files."""
    files = []
    for root, dirs, filenames in os.walk(vault_path):
        # Skip hidden and special directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if fn.startswith(".") or fn in SKIP_FILES:
                continue
            if fn.endswith(".md"):
                files.append(Path(root) / fn)
    return files


def index_vault(vault_path: Path, fts: FTSIndex, vector: VectorIndex = None,
                force: bool = False) -> dict:
    """Index or incrementally update the vault search index."""
    files = collect_vault_files(vault_path)
    indexed_paths = set()
    stats = {"added": 0, "updated": 0, "removed": 0, "skipped": 0, "errors": 0}

    for fpath in files:
        str_path = str(fpath)
        indexed_paths.add(str_path)

        try:
            content_hash = file_hash(fpath)
            if not force and not fts.needs_update(str_path, content_hash):
                stats["skipped"] += 1
                continue

            text = fpath.read_text(encoding="utf-8", errors="replace")
            meta, body = parse_frontmatter(text)

            title = meta.get("title", fpath.stem)
            project = meta.get("project", "")
            if isinstance(project, list):
                project = ", ".join(project)
            doc_type = meta.get("type", "")
            if isinstance(doc_type, list):
                doc_type = ", ".join(doc_type)
            tags = meta.get("tags", "")
            if isinstance(tags, list):
                tags = ", ".join(tags)
            mtime = fpath.stat().st_mtime

            fts.upsert(str_path, content_hash, title, body, project, doc_type, tags, mtime)

            if vector:
                vector.upsert(str_path, f"{title}\n\n{body}", {
                    "path": str_path,
                    "title": title,
                    "project": project,
                    "type": doc_type,
                    "tags": tags,
                })

            stats["added" if not fts.needs_update(str_path, content_hash) else "updated"] += 1

        except Exception as e:
            stats["errors"] += 1
            print(f"  ! Error indexing {fpath.name}: {e}", file=sys.stderr)

    # Remove deleted files from index
    stale = fts.all_paths() - indexed_paths
    for stale_path in stale:
        fts.remove(stale_path)
        if vector:
            vector.remove(stale_path)
        stats["removed"] += 1

    fts.commit()
    return stats


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def format_results(results: list[dict], vault_path: str) -> str:
    """Format search results for display."""
    if not results:
        return "No results found."

    lines = []
    for i, r in enumerate(results, 1):
        # Make path relative to vault
        rel = r["path"].replace(vault_path + "/", "")
        title = r["title"] or os.path.basename(r["path"])
        meta_parts = []
        if r.get("project"):
            meta_parts.append(f"project:{r['project']}")
        if r.get("type"):
            meta_parts.append(f"type:{r['type']}")
        if r.get("tags"):
            meta_parts.append(f"tags:{r['tags']}")
        meta_str = f"  ({', '.join(meta_parts)})" if meta_parts else ""

        lines.append(f"\n{'='*60}")
        lines.append(f"  [{i}] {title}{meta_str}")
        lines.append(f"  File: {rel}")
        if r.get("snippet"):
            snippet = r["snippet"].replace(">>>", "\033[1m").replace("<<<", "\033[0m")
            wrapped = textwrap.fill(snippet, width=72, initial_indent="  > ", subsequent_indent="  > ")
            lines.append(wrapped)

    lines.append(f"\n{'='*60}")
    lines.append(f"  {len(results)} result(s)")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Search your Brain vault by meaning",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""
            Examples:
              brain-search "why did we switch frameworks"
              brain-search "rate limiting" --project Trading-Post
              brain-search "error handling pattern" --type pitfall --limit 10
              brain-search --reindex
              brain-search --stats
        """)
    )
    parser.add_argument("query", nargs="?", help="Search query")
    parser.add_argument("--limit", "-n", type=int, default=5, help="Max results (default: 5)")
    parser.add_argument("--project", "-p", help="Filter by project name")
    parser.add_argument("--type", "-t", help="Filter by document type (e.g., pitfall, daily-note, project)")
    parser.add_argument("--reindex", action="store_true", help="Force full reindex")
    parser.add_argument("--stats", action="store_true", help="Show index statistics")
    parser.add_argument("--vault", help="Override BRAIN_PATH")
    parser.add_argument("--mode", choices=["fts", "vector", "hybrid"], default="hybrid",
                        help="Search mode: fts (full-text), vector (semantic), hybrid (both)")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")

    args = parser.parse_args()

    vault_path = args.vault or BRAIN_PATH
    if not vault_path:
        print("Error: BRAIN_PATH not set. Export BRAIN_PATH or use --vault.", file=sys.stderr)
        sys.exit(1)

    vault = Path(vault_path)
    if not vault.is_dir():
        print(f"Error: Vault not found at {vault_path}", file=sys.stderr)
        sys.exit(1)

    db_path = str(vault / ".brain-search.db")
    vector_dir = str(vault / ".brain-search-vectors")

    # Initialize indexes
    fts = FTSIndex(db_path)

    vector = None
    if _try_import_vector() and args.mode in ("vector", "hybrid"):
        try:
            vector = VectorIndex(vector_dir)
        except Exception as e:
            print(f"  Note: Vector search unavailable ({e}). Using full-text only.", file=sys.stderr)

    # Auto-index on first use or if stale (>1 hour since last index)
    auto_index = False
    if args.reindex:
        auto_index = True
    else:
        idx_stats = fts.stats()
        if idx_stats["total"] == 0:
            auto_index = True
        elif idx_stats["newest_index"] and (time.time() - idx_stats["newest_index"]) > 3600:
            auto_index = True

    if auto_index:
        print("Indexing vault...", file=sys.stderr)
        stats = index_vault(vault, fts, vector, force=args.reindex)
        total = stats["added"] + stats["updated"]
        print(f"  Indexed: {total} files ({stats['added']} new, {stats['updated']} updated, "
              f"{stats['removed']} removed, {stats['skipped']} unchanged)", file=sys.stderr)
        if stats["errors"]:
            print(f"  Errors: {stats['errors']}", file=sys.stderr)

    if args.stats:
        s = fts.stats()
        print(f"\nBrain Search Index Stats")
        print(f"{'='*40}")
        print(f"  Total documents: {s['total']}")
        print(f"\n  By type:")
        for doc_type, count in s["by_type"]:
            print(f"    {doc_type or '(none)'}: {count}")
        if s["by_project"]:
            print(f"\n  By project (top 10):")
            for proj, count in s["by_project"]:
                print(f"    {proj}: {count}")
        if vector:
            print(f"\n  Vector index: {vector.count()} chunks")
        else:
            print(f"\n  Vector search: not available (pip install chromadb sentence-transformers)")
        fts.close()
        return

    if not args.query:
        parser.print_help()
        fts.close()
        sys.exit(1)

    # Ensure index is current
    if not auto_index:
        stats = index_vault(vault, fts, vector, force=False)

    # Search
    results = []

    if args.mode == "vector" and vector:
        where = {}
        if args.project:
            where["project"] = args.project
        if args.type:
            where["type"] = args.type
        results = vector.search(args.query, limit=args.limit, where=where or None)

    elif args.mode == "hybrid" and vector:
        # Combine FTS and vector results, deduplicate by path
        fts_results = fts.search(args.query, limit=args.limit, project=args.project, doc_type=args.type)
        where = {}
        if args.project:
            where["project"] = args.project
        if args.type:
            where["type"] = args.type
        vec_results = vector.search(args.query, limit=args.limit, where=where or None)

        seen = set()
        for r in fts_results + vec_results:
            if r["path"] not in seen:
                seen.add(r["path"])
                results.append(r)
        results = results[:args.limit]

    else:
        # FTS only
        results = fts.search(args.query, limit=args.limit, project=args.project, doc_type=args.type)

    if args.json:
        import json
        print(json.dumps(results, indent=2, default=str))
    else:
        print(format_results(results, vault_path))

    fts.close()


if __name__ == "__main__":
    main()
