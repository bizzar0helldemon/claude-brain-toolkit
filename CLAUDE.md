# Claude Brain — Personal Knowledge Hub

## Configuration

```bash
# Set your brain path (REQUIRED)
export BRAIN_PATH="{{SET_YOUR_BRAIN_PATH}}"

# Set your Obsidian vault path (OPTIONAL — only if using Obsidian)
# export OBSIDIAN_VAULT="{{SET_YOUR_VAULT_PATH}}"
```

---

## Identity Snapshot

> **[YOUR NAME]** — [YOUR ROLE/TITLE], [YOUR DOMAINS].
>
> **What's known so far:**
> - **Name:** [YOUR NAME]
> - **Career:** [YOUR CAREER SUMMARY — what you do, who you serve]
> - **Creative:** [YOUR CREATIVE DOMAINS — music, writing, art, video, etc.]
> - **Technical:** [YOUR TECH STACK — languages, frameworks, tools you use]
> - **Projects:** [N] projects across [M] categories — see [[Project Index]]
>
> *Run `/brain-intake` to fill this section with real personal details.*

---

## Routing Table

| Need | Go To |
|------|-------|
| Full personal profile | [[Identity Profile]] (`IDENTITY.md`) |
| Creative work | [[Creative Works Index]] (`creative/_INDEX.md`) |
| All dev/creative projects | [[Project Index]] (`projects/_INDEX.md`) |
| Career portfolio | `portfolio/` directory |
| Daily journal / session logs | `daily_notes/` directory |
| Intake sessions & discovery | [[Intake System Index]] (`intake/_INDEX.md`) |
| AI frameworks & governance | `frameworks/` directory |
| Prompt & pattern library | [[Prompt & Pattern Library]] (`prompts/_INDEX.md`) |
| Templates & conventions | `brain-scan-templates.md` |

---

## Project Categories

| Category | Count | Summary |
|----------|-------|---------|
| **Music** | 0 | |
| **Writing** | 0 | |
| **Video** | 0 | |
| **Creative** | 0 | |
| **Hardware** | 0 | |
| **Dev Tools** | 0 | |
| **Apps** | 0 | |
| **Games** | 0 | |
| **Business** | 0 | |

---

## Active Focus Areas

1. [Update periodically — what are the top 3-5 current priorities?]
2. [e.g., "Album project — finishing lyrics phase"]
3. [e.g., "Brain expansion — building out personal knowledge hub"]

---

## Working With This Person

> [NEEDS INTAKE] Capture through `/brain-intake` sessions.

- [Communication style preferences]
- [Work style preferences]
- [Humor / tone preferences]
- [What you want Claude to know about you beyond your code]
- [Anything else that helps Claude work with you effectively]

---

## Obsidian Linking Conventions

- **People** — always `[[First Last]]` or `[[Nickname]]`
- **Projects** — `[[Project Name]]` matching the .md filename's frontmatter title
- **Groups** — `[[Group Name]]`, etc.
- **Tags** — consistent frontmatter `tags:` array (kebab-case values)
- **File naming** — kebab-case for files, Title Case for display via frontmatter `title:`
- **Cross-links** — related documents link to each other, projects link to people, indexes link to entries

---

## Vault Tools & Commands

### Obsidian CLI (Optional)

If you use Obsidian and have `obsidian-cli` installed:

```bash
export OBSIDIAN_VAULT="{{SET_YOUR_VAULT_PATH}}"
```

| Task | Command |
|------|---------|
| Find note | `obsidian-cli find "search term"` |
| Read note | `obsidian-cli cat "Note Name"` |
| Create note | `obsidian-cli new "Note Name"` |
| View frontmatter | `obsidian-cli meta "Note Name"` |
| Set property | `obsidian-cli meta "Note Name" --key tags --value "tag1, tag2"` |
| Query by property | `obsidian-cli query tags --contains "tagname"` |
| Daily note | `obsidian-cli journal` |
| Rename + fix links | `obsidian-cli rename --link "Old" "New"` |

### Best Practices

1. Use `obsidian-cli cat` to read notes (resolves page names)
2. Use `obsidian-cli find` before reading to confirm note exists
3. Use `--style json` on `query` commands when parsing programmatically
4. Use Write/Edit tools for creating notes with specific content
5. Use Grep tool for full-text search, backlink discovery, inline tags

---

## Vault Location

- **Brain Path:** `{{SET_YOUR_BRAIN_PATH}}`
- **Obsidian Vault:** `{{SET_YOUR_VAULT_PATH}}` *(optional)*
- **Tool:** `obsidian-cli` *(optional — install via npm if using Obsidian)*
