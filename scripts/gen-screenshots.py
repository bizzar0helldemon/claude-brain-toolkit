#!/usr/bin/env python3
"""
Generate clean, privacy-safe terminal-style SVG screenshots for the README.

Everything here is a mockup: placeholder repo names ("my-app"), no real paths,
no personal data. Colors mirror the toolkit's own statusline (256-color -> hex).
Re-run to regenerate: python3 scripts/gen-screenshots.py
"""
import html
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "screenshots")
os.makedirs(OUT, exist_ok=True)

# ── Palette (mirrors statusline.sh 256-color codes) ──────────────
BG      = "#0f1117"   # terminal background
BG2     = "#161922"   # inset panel background
CHROME  = "#1c1f2b"   # title bar
BORDER  = "#262a38"
CYAN    = "#87afff"   # 117 brain brand
PURPLE  = "#d7afff"   # 183 model
GREEN   = "#87d787"   # 114 additions / good
YELLOW  = "#ffd75f"   # 221 warning
RED     = "#ff5f5f"   # 203 danger
DIM     = "#8a8a8a"   # 245 separators
WHITE   = "#e6e6e6"   # 255 neutral text
BLUE    = "#5fafff"   # 75 worktree
MUTED   = "#6b7280"
PROMPT  = "#5fd7af"   # user prompt marker
FONT    = "ui-monospace, 'SF Mono', 'Cascadia Code', 'JetBrains Mono', Menlo, Consolas, monospace"

CH = 8.4     # char width at 14px
LH = 22      # line height
PAD_X = 26
PAD_TOP = 52

def esc(s):
    return html.escape(s, quote=True)

def span(text, color=WHITE, bold=False, italic=False):
    return {"t": text, "c": color, "b": bold, "i": italic}

def line(*spans):
    return list(spans)

def blank():
    return []

def render(name, title, lines, width=860, subtitle_dot=True, highlights=None):
    """lines: list of lists of span dicts (or [] for blank line).
    highlights: optional dict {line_index: bg_hex} to draw a selection bar."""
    highlights = highlights or {}
    height = PAD_TOP + LH * len(lines) + 22
    parts = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="{FONT}" font-size="14">'
    )
    # window
    parts.append(f'<rect x="0" y="0" width="{width}" height="{height}" rx="12" fill="{BG}" stroke="{BORDER}"/>')
    # title bar
    parts.append(f'<rect x="0" y="0" width="{width}" height="38" rx="12" fill="{CHROME}"/>')
    parts.append(f'<rect x="0" y="20" width="{width}" height="18" fill="{CHROME}"/>')
    parts.append(f'<line x1="0" y1="38" x2="{width}" y2="38" stroke="{BORDER}"/>')
    # traffic lights
    for i, col in enumerate(["#ff5f56", "#ffbd2e", "#27c93f"]):
        parts.append(f'<circle cx="{22 + i*20}" cy="19" r="6" fill="{col}"/>')
    # title text
    parts.append(
        f'<text x="{width/2}" y="24" text-anchor="middle" fill="{DIM}" font-size="12.5">{esc(title)}</text>'
    )
    # body lines
    y = PAD_TOP
    for idx, ln in enumerate(lines):
        if idx in highlights:
            parts.append(
                f'<rect x="12" y="{y - 16}" width="{width - 24}" height="{LH}" rx="4" '
                f'fill="{highlights[idx]}"/>'
            )
        x = PAD_X
        for sp in ln:
            style = ""
            if sp["b"]:
                style += ' font-weight="700"'
            if sp["i"]:
                style += ' font-style="italic"'
            parts.append(
                f'<text x="{x:.1f}" y="{y}" fill="{sp["c"]}"{style} '
                f'xml:space="preserve">{esc(sp["t"])}</text>'
            )
            x += len(sp["t"]) * CH
        y += LH
    parts.append("</svg>")
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write("\n".join(parts))
    print("wrote", os.path.relpath(path))


# ══════════════════════════════════════════════════════════════════
# 1. STATUSLINE — the two-row branded display
# ══════════════════════════════════════════════════════════════════
def sep():
    return span("  │  ", DIM)

render(
    "statusline.svg",
    "statusline — two-row brain display",
    [
        blank(),
        line(span("🧠 Brain", CYAN, bold=True), sep(),
             span("📂 my-app", WHITE), span("  🌿 ", DIM), span("main", CYAN), sep(),
             span("🤖 Opus 4.8", PURPLE)),
        line(span("🟢 captured", GREEN), sep(),
             span("▓▓▓▓▓▓", GREEN), span("░░░░", DIM), span(" 62%", WHITE), sep(),
             span("+47", GREEN), span(" ", DIM), span("-12", RED), sep(),
             span("📝 3", YELLOW), sep(),
             span("⏱ 14m", WHITE)),
        blank(),
        line(span("Row 1", MUTED, italic=True), span("  brand · repo + branch (worktree-aware) · model", DIM)),
        line(span("Row 2", MUTED, italic=True), span("  brain state · context bar · lines · dirty files · time", DIM)),
        blank(),
    ],
    width=760,
)

# ══════════════════════════════════════════════════════════════════
# 2. SESSION START — vault context loads automatically
# ══════════════════════════════════════════════════════════════════
render(
    "session-start.svg",
    "session start — memory loads before you type",
    [
        blank(),
        line(span("$ ", PROMPT), span("claude --agent brain-mode", WHITE)),
        blank(),
        line(span("▸ ", CYAN), span("Brain: loaded", CYAN, bold=True),
             span("  (4 projects, 3 pitfalls, 6 patterns in context)", DIM)),
        blank(),
        line(span("  Active focus", WHITE, bold=True)),
        line(span("   • ", CYAN), span("my-app", WHITE), span("      auth refactor — waiting on review", DIM)),
        line(span("   • ", CYAN), span("data-pipe", WHITE), span("    backfill job, phase 2 of 3", DIM)),
        blank(),
        line(span("  Pitfalls to remember", WHITE, bold=True)),
        line(span("   ! ", YELLOW), span("staging DB migrations must run before deploy, not after", DIM)),
        line(span("   ! ", YELLOW), span("the flaky e2e test needs RETRIES=2, not a skip", DIM)),
        blank(),
        line(span("Ready. What are we working on?", WHITE)),
        blank(),
    ],
    width=820,
)

# ══════════════════════════════════════════════════════════════════
# 3. ERROR RECALL — past solution surfaces on failure
# ══════════════════════════════════════════════════════════════════
render(
    "error-recall.svg",
    "error pattern recall — it remembers the fix",
    [
        blank(),
        line(span("$ ", PROMPT), span("npm run build", WHITE)),
        line(span("Error: ", RED), span("ENOSPC: System limit for number of file watchers reached", WHITE)),
        blank(),
        line(span("▸ ", CYAN), span("Brain: found past solution for this error", CYAN, bold=True),
             span("  (seen 1× before)", DIM)),
        blank(),
        line(span("  I've hit this before. The fix that worked:", WHITE)),
        blank(),
        line(span("    $ ", MUTED), span("echo fs.inotify.max_user_watches=524288 \\", GREEN)),
        line(span("        | sudo tee -a /etc/sysctl.conf", GREEN)),
        line(span("    $ ", MUTED), span("sudo sysctl -p", GREEN)),
        blank(),
        line(span("  Raises the inotify watcher limit — the watcher-based", DIM)),
        line(span("  builder exhausts the default 8192 on large trees.", DIM)),
        blank(),
    ],
    width=820,
)

# ══════════════════════════════════════════════════════════════════
# 4. SAFETY HOOKS — dangerous command + secret leak blocked
# ══════════════════════════════════════════════════════════════════
render(
    "safety-hooks.svg",
    "safety hooks — mistakes blocked before they run",
    [
        blank(),
        line(span("$ ", PROMPT), span("git reset --hard origin/main", WHITE)),
        line(span("⛔ BLOCKED ", RED, bold=True), span("risk-classifier", DIM)),
        line(span("   Destructive: discards all uncommitted work.", WHITE)),
        line(span("   Stash or commit first, then re-run intentionally.", DIM)),
        blank(),
        line(span("$ ", PROMPT), span("git commit -m \"add config\"", WHITE)),
        line(span("⛔ BLOCKED ", RED, bold=True), span("pre-commit-secrets", DIM)),
        line(span("   Staged diff contains a secret:", WHITE)),
        line(span("     config/prod.env:4  ", DIM), span("AWS_SECRET_ACCESS_KEY=****", YELLOW)),
        line(span("   Remove it and add the file to .gitignore.", DIM)),
        blank(),
        line(span("✓ ", GREEN), span("Nothing destructive ran. No secret was committed.", DIM)),
        blank(),
    ],
    width=820,
)

# ══════════════════════════════════════════════════════════════════
# 5. SILENT CAPTURE — session end writes to the vault itself
# ══════════════════════════════════════════════════════════════════
render(
    "capture.svg",
    "silent capture — knowledge compounds on its own",
    [
        blank(),
        line(span("  …fixed the race condition and the tests pass.", WHITE)),
        blank(),
        line(span("▾ ", CYAN), span("Brain: captured 2 learnings, daily note updated", CYAN, bold=True)),
        blank(),
        line(span("   learnings/", DIM), span("concurrency-retry-idempotency.md", WHITE),
             span("   new", GREEN)),
        line(span("   projects/", DIM), span("my-app.md", WHITE),
             span("                    updated", YELLOW)),
        line(span("   daily_notes/", DIM), span("2026-07-07.md", WHITE),
             span("             appended", YELLOW)),
        blank(),
        line(span("   No command to run — capture is mechanical.", DIM, italic=True)),
        line(span("   Next session starts already knowing this.", DIM, italic=True)),
        blank(),
    ],
    width=820,
)

# ══════════════════════════════════════════════════════════════════
# 6. DASHBOARD — the `brain` fzf launcher
# ══════════════════════════════════════════════════════════════════
SEL = "#20242f"   # fzf selection bar
PTR = "#5fd7af"   # fzf pointer color

def div(label):
    return line(span("   ── " + label + " ", DIM), span("─" * (46 - len(label)), BORDER))

def item(icon, name, desc, selected=False):
    ptr = span(" ▎ ", PTR) if selected else span("   ", BG)
    nm_c = WHITE if selected else WHITE
    return line(ptr, span(icon + "  ", WHITE), span(name.ljust(24), nm_c),
                span(desc, DIM))

render(
    "dashboard.svg",
    "brain — the launcher dashboard",
    [
        blank(),
        line(span("$ ", PROMPT), span("brain", WHITE)),
        blank(),
        line(span("🧠 brain ▸ ", CYAN, bold=True), span("▏", WHITE)),
        line(span("  15/15", MUTED), span("   Brain Dashboard — my-vault", DIM)),
        blank(),
        div("Onboarding"),
        item("🎬", "Onboard me", "guided walkthrough: identity → content → projects"),
        item("👤", "Who you are", "guided identity interview"),
        item("📂", "Catalog a project", "add / refresh a project note"),
        div("Work"),
        item("🚀", "Launch project", "new window, brain session in project dir", selected=True),
        item("🧠", "Brain session here", "start brain-mode in the current dir"),
        item("🔍", "Search vault", "full-text + semantic search"),
        item("⚡", "Quick capture", "drop a note into the inbox"),
        div("Maintain"),
        item("📊", "Vault health", "quick stats snapshot"),
        item("🎮", "Game night", "riddles, crosswords, quest campaign"),
        blank(),
    ],
    width=820,
    highlights={11: SEL},
)

# ── 6b. DASHBOARD RESULT — after picking a project ───────────────
render(
    "dashboard-launch.svg",
    "brain — project launched in a new window",
    [
        blank(),
        line(span("🧠 brain ▸ ", CYAN, bold=True), span("Launch project", DIM)),
        blank(),
        line(span("  project ▸ ", CYAN), span("my-app", WHITE)),
        blank(),
        line(span("  ↗ ", GREEN, bold=True),
             span("Launched in new window: ", WHITE),
             span("~/code/my-app", CYAN)),
        blank(),
        line(span("     opening ", DIM), span("🧠 brain-mode", CYAN),
             span(" session — memory loading…", DIM)),
        blank(),
        line(span("  ─────────────────────────────────────────────", BORDER)),
        line(span("  new window", MUTED, italic=True),
             span("   cd'd into the project, brain session running,", DIM)),
        line(span("            ", MUTED),
             span("   interactive shell left behind on exit", DIM)),
        blank(),
        line(span("🧠 brain ▸ ", CYAN, bold=True), span("▏", WHITE)),
        blank(),
    ],
    width=820,
)

print("done")
