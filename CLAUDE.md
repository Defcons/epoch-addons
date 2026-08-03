# Claude Code — Ascension WoW 3.3.5 Addon Project

## Environment

- **Server:** Ascension private server (WoW 3.3.5 client)
- **Interface version:** 30300
- **Lua version:** 5.1 (no Lua 5.2+ features)
- **Repo path:** `C:\Private\Games\Ascension Launcher\resources\epoch_live\Interface\Addons\`
- **Branch:** master
- **Tracked addons only** — all unmodified addons are excluded via `.gitignore`

---

## Session Workflow

Follow these steps every session:

1. Add an inline comment `-- Claude: <short description>` on or near every changed line
2. At the end of each session, update `CHANGELOG.md` in the repo root
3. Commit with a descriptive message: `git add <files> && git commit -m "..."`
4. Run `git status` before finishing to confirm nothing was left uncommitted

---

## Deeper docs — architecture, API gotchas, per-addon facts, invariants

**This file is env/workflow only.** Everything else lives in the triad — don't
duplicate it here:

- **`OrientationMap.md`** — where code lives (addon → folder + key symbols), invariants,
  ordering constraints, cross-cutting flows, contracts, and known landmines.
- **`KnowledgeBase.md`** — what's true: the platform contract + the **full 3.3.5
  API-incompatibility reference + code** (§2 / §2.1), cross-cutting behavioural
  truths (§3), the per-addon truth index (§4), and the **per-addon deep notes +
  SavedVariables quick-reference** (§9).
- **`ResearchJournal.md`** — the history: milestones, lessons, known-issue chronology.

Read `OrientationMap.md` + `KnowledgeBase.md` before touching any tracked addon.

---

## Other Projects

- **epoglogs** (formerly labelled "warcraftlogs-epog"): `C:\Dev\games\wow\epoglogs` — combat log viewer for epoglogs.com. Use this path for all file edits and git operations for that project.
- **epog-data:** `C:\Dev\games\wow\epog-data` — shared DBC extraction toolkit. Consumed by armory + logs via `npm run publish`.
- **epogarmory-web:** `C:\Dev\games\wow\epogarmory-web` — static armory viewer. Consumes EpogArmory addon SavedVariables uploads.
