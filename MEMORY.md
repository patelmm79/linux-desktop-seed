# MEMORY.md — Long-Term Memory

_Curated across sessions and projects. Not project-specific — this is the overlay that applies everywhere._

---

## About the User

- **Name:** no_decaf_milan (Discord: 1162240440322502656)
- **Primary channel:** `#globalbitings` Discord server (Guild: 1485047825967480862)
- **VM:** Ubuntu at `~/GithubProjects/` — multiple projects live here
- **Owner of:** `patelmm79/GlobalBitings` on GitHub
- **Communication style:** Direct, asks for status checks, wants me to be proactive about my own gaps

---

## AI Interaction Process (Non-Negotiable Habits)

These override any default behavior. I follow these every session.

### Memory Protocol
1. At the **start** of any non-trivial task → write one line to `memory/YYYY-MM-DD.md`: what I'm doing, which files, next step
2. After any meaningful milestone → update `memory/YYYY-MM-DD.md`
3. If asked "what were you working on" and memory is empty → check `~/.openclaw/agents/main/sessions/` transcript before answering "I don't know"
4. Keep `MEMORY.md` (this file) updated with cross-project context — reviewed at session start

### Session Survival Rules
1. **Git commit partial work** — not just complete work. A half-built script that's committed is recoverable. One only in memory is lost.
2. **Long-running jobs → `background: true`** — any process that takes >30s runs as background job to avoid session timeouts
3. **Batch similar operations** — multiple git ops, file writes, or web searches in one turn are cheaper than across sessions
4. **Session compaction awareness** — when context fills (~200k tokens), the session compacts and loses in-progress context. Keep sessions focused on one area

### How to Receive Tasks
- Specific, bounded tasks with a defined "done" state → I execute fastest this way
- Open-ended goals → I need a defined end state before I can be effective
- Check existing files before building — don't assume I know what's already there

---

## VM-Level Setup (OpenClaw)

- **OpenClaw version:** 2026.3.28
- **Gateway running:** Yes, port 8000 for FastAPI services
- **Workspace:** `~/.openclaw/workspace/`
- **Daily session logs:** `~/.openclaw/agents/main/sessions/` (JSONL transcript files)
- **Per-project memory:** `~/.openclaw/workspace/memory/YYYY-MM-DD.md`
- **Long-term memory:** `~/.openclaw/workspace/MEMORY.md` (this file)
- **Disaster recovery:** `~/DISASTER_RECOVERY.md`

---

## All Active Projects & Channels

### Discord Channels (via OpenClaw)

| Channel / Topic | Session File | Last Active | Status |
|----------------|-------------|-------------|--------|
| `#globalbitings` | `e27582e9-...jsonl` (648K) | 2026-04-01 | Active — see `memory/2026-04-01.md` |
| `topic-1488912848821289061` | `415cdce1-...jsonl` (92K) | 2026-04-01 | Art applications |
| `topic-1488909017270059119` | `1b946718-...jsonl` (56K) | 2026-04-01 | Art stuff |
| `topic-1488635028702232816` | `de0a6a4e-...jsonl` (764K) | 2026-04-01 | Compliance repo creation — largest session |
| `topic-1488628990301442160` | `8a74503a-...jsonl` (36K) | 2026-03-31 | Knowledge research |
| `topic-1488629512718782564` | `c06bd011-...jsonl` (32K) | 2026-03-31 | Knowledge research |

### GitHub Repos (`~/GithubProjects/`)

| Repo | Notes |
|------|-------|
| `GlobalBitings` | Dish-first restaurant discovery. Active. See `memory/2026-04-01.md` |
| `bond-nexus` | Has CLAUDE.md — not yet explored |
| `dev-nexus` | FastAPI A2A backend for Pattern Discovery Agent System |
| `dev-nexus-frontend` | React+TS frontend. Active — Readiness Dashboard, Build New Project. See `memory/channels/dev-nexus-frontend.md` |
| `elastica` | Has CLAUDE.md — not yet explored |
| `gcp-postgres-terraform` | Has CLAUDE.md — not yet explored |
| `_backup_gcp_postgres` | Backup, no CLAUDE.md |
| `gcp-postgres-terraform` | Terraform for GCP Postgres |

---

## Per-Channel / Per-Project Summaries

### `#globalbitings` — most recent session
**Full detail:** `memory/2026-04-01.md`
- Dish-first restaurant discovery app
- 5,682 dish knowledge graph built
- 22,726 restaurants seeded across 5 cities
- Blog extraction pipeline built (needs testing)
- FastAPI backend running on port 8000

### `#dev-nexus-frontend` (2026-04-02)
**Full detail:** `memory/channels/dev-nexus-frontend.md`
- React+TS frontend for Pattern Discovery Agent System
- Recent work: Readiness Dashboard, Build New Project page, user preferences/API keys
- Repo clean, backend not running locally

### `topic-1488635028702232816` — largest session (764K)
**Not yet reviewed.** Full summary not captured. Check session transcript for details.

### `topic-1488912848821289061` — Art applications
**Not yet reviewed.** Check session transcript.

### `topic-1488909017270059119` — Art stuff
**Not yet reviewed.** Check session transcript.

### `topic-1488628990301442160` + `topic-1488629512718782564` — Knowledge research
**Not yet reviewed.** Check session transcripts.

---

## Disaster Recovery Process

If OpenClaw workspace is lost or reset:

1. **Recover from git** → `~/GithubProjects/*` repos have all committed code and docs
2. **Recover session history** → `~/.openclaw/agents/main/sessions/*.jsonl` — full transcript of every session
3. **Recover daily context** → `~/.openclaw/workspace/memory/*.md` — per-session logs
4. **Recover this file** → `~/.openclaw/workspace/MEMORY.md` (this file is the anchor)
5. **Recover channel summaries** → `~/.openclaw/workspace/memory/channels/` — per-channel summaries

### Backup Schedule
- Memory files are workspace-local and NOT git-ignored. Commit them to a backup repo or sync externally.
- `memory/` directory: contains daily session logs — back these up if workspace is reset
- Key disaster recovery info also saved to: `~/DISASTER_RECOVERY.md`

---

## Personal Preferences & Notes

- Prefers direct communication — no filler words
- Likes proactive status updates without being asked
- Willing to let me operate autonomously within the workspace
- Asks "status?" frequently — check VM processes and git log for full picture
