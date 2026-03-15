---
name: brain-discover
description: Scan drives for existing creative content not yet in the brain. Finds documents, scripts, writing, and other files that should be cataloged.
argument-hint: <path-to-scan>
---

# Brain Discover — Drive Content Scanner

You are scanning a path for existing creative content that hasn't been captured in the Claude Brain yet.

## Your Task

The user provides a path to scan (as $ARGUMENTS). You must find content files, present them grouped by type, and help the user decide what to ingest.

## Step-by-Step Process

### Step 1: Scan the Path

Search the provided path recursively for content files:

**File types to look for:**
- `.md`, `.txt` — writing, notes, scripts
- `.odt` — OpenOffice text documents (convert to markdown before reading — see ODT Conversion below)
- `.doc`, `.docx` — documents (note: can't read contents, but can catalog)
- `.pdf` — documents, scripts
- `.py`, `.js`, `.html` — code that might be creative projects
- `.json` — structured data (comic scripts, game data, etc.)
- `.lrc`, `.srt` — lyrics, subtitles
- `.wma`, `.mp3`, `.wav`, `.m4a`, `.ogg`, `.flac` — audio recordings (transcribe with Whisper — see Audio Transcription below)

**Ignore:**
- `node_modules/`, `.git/`, `__pycache__/`, `.obsidian/`
- Image files (`.png`, `.jpg`, `.gif`, `.bmp`) — note their existence but don't try to read
- Video files (`.mp4`, `.avi`, `.mkv`, `.mov`) — note their existence but don't try to read
- System files, configs, lockfiles

### Step 2: Categorize Findings

Group discovered files by apparent content type:

| Category | Indicators |
|----------|-----------|
| Scripts/Dialogue | Dialogue format, character names, stage directions |
| Writing | Prose, stories, essays, blog posts |
| Music/Lyrics | Song structure, verse/chorus, musical references |
| Project docs | READMEs, specs, design docs |
| Personal | Journal entries, notes, reflections |
| Audio recordings | `.wma`, `.mp3`, `.wav`, `.m4a` — voice notes, interviews, brainstorms |
| Unknown | Can't determine — ask user |

### Step 3: Present to User

Show findings in a clear, grouped format:

```
## Discovery Results: [path]

### Scripts / Dialogue (N files)
- `path/to/file.md` — [brief description of contents]
- `path/to/file.txt` — [brief description]

### Writing (N files)
- ...

### Already in Brain (N files)
- [files that match existing project entries]

### Skipped (N files/dirs)
- [binary files, system files, etc.]

**What would you like to ingest?** (Enter numbers, "all", or "none")
```

### Step 4: Ingest Selected Content

For each selected file:

1. **Determine destination:**
   - Scripts/dialogue → `creative/scripts/[slug].md`
   - Writing → `creative/writing/[slug].md`
   - Music ideas → `creative/music-ideas/[slug].md`
   - Video concepts → `creative/video-concepts/[slug].md`
   - Project-related → update existing `projects/` entry or create new via `/brain-scan`

2. **Create proper entry** with:
   - Frontmatter (title, date, type, tags, related)
   - `[[wiki links]]` to people, projects, groups mentioned
   - Content from the source file (reformatted to template if needed)

3. **Update indices:**
   - Add to `creative/_INDEX.md` if creative content
   - Add to `projects/_INDEX.md` if a new project
   - Update `IDENTITY.md` if personal information discovered

### Step 5: Log the Discovery

Save a discovery log to:
```
intake/discoveries/YYYY-MM-DD-[path-slug].md
```

```markdown
---
title: "Discovery: [Path Scanned]"
date: YYYY-MM-DD
path: "[full path]"
type: discovery-log
tags: [intake, discovery]
files-found: N
files-ingested: N
---

# Discovery: [Path]

## Summary
- **Scanned:** [path]
- **Files found:** N
- **Files ingested:** N
- **Files skipped:** N

## Ingested
- `source-path` → `brain-path` — [description]

## Skipped
- `source-path` — [reason: already in brain / binary / user declined]
```

### Step 6: Report

```
## Discovery Complete

**Path scanned:** [path]
**Files found:** N
**Files ingested:** N into [list of brain locations]
**Discovery log:** intake/discoveries/YYYY-MM-DD-path.md
```

## ODT Conversion

When `.odt` files are found, convert them to markdown using pandoc before reading:

```bash
pandoc "path/to/file.odt" -t markdown
```

**Prerequisite:** Install pandoc (`winget install JohnMacFarlane.Pandoc` on Windows, `brew install pandoc` on macOS, `apt install pandoc` on Linux).

**Process:**
1. Convert the `.odt` file to markdown via pandoc (outputs to stdout)
2. Read the converted markdown content
3. Use it the same way you'd use any `.md` file — categorize, present to user, ingest if selected
4. When ingesting, save as `.md` in the brain with proper frontmatter — do NOT copy the `.odt` file itself

**Notes:**
- Pandoc preserves headings, lists, bold/italic, and basic formatting
- Some `.odt` files may have complex tables or embedded images — pandoc handles tables, images are noted as `![](...)` references
- If pandoc fails on a file, log it as "conversion failed" and skip — don't block the whole scan
- The original `.odt` file is never modified or moved

## Audio Transcription

When audio files are found (`.wma`, `.mp3`, `.wav`, `.m4a`, `.ogg`, `.flac`), transcribe them using OpenAI Whisper.

**Prerequisite:** Install Whisper (`pip install openai-whisper`). Requires Python 3.8+ and ffmpeg. GPU (CUDA) strongly recommended for batch work.

### Transcription Command

```bash
whisper "path/to/audio.wma" --model medium --output_format txt --output_dir "path/to/output/"
```

**Model selection:**
- `medium` — recommended for batch work. Good accuracy, reasonable speed on consumer GPUs
- `base` — fast, lower accuracy. Use for quick previews or when speed matters
- `large-v3` — highest accuracy but slow on consumer GPUs. Only use for single important files
- Do NOT use `large` for batch transcription unless you have a high-end GPU

### Process

1. **Present audio files to the user** in the discovery results under an "Audio Recordings" category
2. **Ask before transcribing** — transcription takes time. Let the user pick which files to process
3. **Transcribe selected files** using whisper with the `medium` model by default
4. **Check for existing transcripts** — look for a `transcripts/` subdirectory next to the audio files. If a transcript already exists for a file, skip it and read the existing transcript instead
5. **Read the transcript text** and categorize/ingest it the same way as any text content
6. **When ingesting**, save to the brain as `.md` with frontmatter including:
   - `type: audio-transcript`
   - `source:` path to original audio file
   - `transcribed-with: whisper-medium`

### Batch Handling

If more than 10 audio files are found:
1. Show the count and ask if the user wants to transcribe all, select specific files, or skip audio
2. If transcribing a large batch, offer to run whisper in the background using `run_in_background`
3. Report progress: "Transcribing file X of Y..."

### Error Handling
- If whisper fails on a file (corrupt audio, unsupported codec), log it and continue
- If CUDA runs out of memory, fall back to `base` model
- The original audio file is never modified or moved

## Important Notes

- **Don't move or delete source files** — only copy/create brain entries
- **Ask before ingesting** — always let the user choose what comes in
- **Add [[wiki links]]** to everything — people, projects, groups
- **Check for duplicates** — compare against existing `projects/` entries before creating new ones
- **Large directories** — if >100 files found, show counts by category and ask user to narrow scope

---

**Usage:** `/brain-discover [path]`

Examples:
- `/brain-discover ~/Documents/Writing` — scan for writing
- `/brain-discover ~/Desktop` — scan desktop for uncataloged content
- `/brain-discover /mnt/archive` — scan an archive drive (may be large)
