# Epoch Addons — Research Journal

_The chronological history of this addon collection: what shipped when, the
milestones, and the hard-won lessons behind them. Append-only. The DISTILLED
current truth lives in [`KnowledgeBase.md`](KnowledgeBase.md); the code index in
[`CodeMap.md`](CodeMap.md). The triad: **CodeMap = the machine · KnowledgeBase =
the model · ResearchJournal = the history.**_

> **Reconcile note:** the rich, per-session, per-addon narrative already exists in
> [`CHANGELOG.md`](CHANGELOG.md) (165 dated entries). This journal does NOT
> duplicate it — it is the **milestone-level timeline + the lessons** distilled
> from `git log` (284 commits) and that changelog. For "exactly what changed in
> addon X on date Y", read `CHANGELOG.md`.

_Last verified: 2026-08-03 @ 8223a48 (master) — seeded from git history + CHANGELOG
as the DEEP-pass chronology layer._

---

## Timeline at a glance

| Period | Commits | What happened |
|---|---:|---|
| 2026-03 | 78 | Initial import; CHANGELOG reconstructed from code analysis; first bulk port/fix wave |
| 2026-04 | 102 | Peak activity; **EpogArmory born** (v1.5 rename from EpochArmory, 04-22); heavy porting |
| 2026-05 | 97 | EpogArmory dummy-parse/dungeon/raid tooling; **EpochSynch/PEBGSync** BG-sync; unitscan Ascension fixes |
| 2026-06 | 5 | EpogArmory v2.0.x (dungeon minimize, whisper-spam, auto-log defaults) |
| 2026-07 | 1 | `CODE-MAP.md` added (durable facts migrated from cross-project notes) |
| 2026-08 | 1 | Triad: `CODE-MAP.md` → `CodeMap.md`; this KB + Journal seeded |

Full span: **2026-03-21 → 2026-08-03**, 284 commits, 29 tracked addons.

---

## Milestones & lessons (distilled)

### M0 — Foundation (2026-03-21)
Initial commit of all addons; then immediately **restricted tracking to modified
addons only** via the `.gitignore` allowlist (default-deny `/*` + `!Addon/`). The
CHANGELOG was **reconstructed from code analysis** (commit `19dd362`), not written
live — so the earliest entries are archaeology, not real-time notes.

### M1 — The bulk port/fix wave (2026-03 → 2026-04, ~180 commits)
The dominant early effort: taking community 3.3.5/retail addons and making them
survive on Ascension. Recurring, cross-cutting **lessons that graduated into
`CLAUDE.md`** and now into the KB:
- **`xpcall` drops varargs on Lua 5.1** — surfaced via an Ace3/ArkInventory crash;
  the fix (`pcall` + manual handler) became a repo-wide pattern.
- **Taint = hook, never raw-replace** — learned the hard way on pfQuest-wotlk;
  raw `QuestLog_Update` replacement taints the UI. Now `hooksecurefunc` everywhere.
- **`GameTooltip` ownership theft** and **inspect-link expiry (~10–15s)** — drove
  EpochFixes' explicit `SetOwner` + 19-slot inspect cache.
- **Quest-log selection drift** on `QUEST_LOG_UPDATE` — EpochFixes re-selects by
  title, not index.
- **Aux temp-table allocator crashes external mass-parse** — spawned **AuxTSMBridge**
  as a deliberate workaround (parse the raw history string, never call Aux).
- Retail-12.0 → 3.3.5 back-port pain (FavoriteContacts): strip `CreateFromMixins`,
  `EventRegistry`, `Settings`, modern atlas icons; hand-roll the equivalents.

### M2 — EpogArmory becomes the flagship (2026-04-22 → 2026-06, 145 commits / 51% of history)
Renamed `EpochArmory → EpogArmory` (v1.5, 04-22) and then built out into the
collection's largest addon — a combat-log / DPS-meter / gear-scan armory. The
build order, from git:
- **Dummy parse validation** (v1.6–v1.7): a target-dummy DPS test that emits a
  combat-log **marker and verifies the parse landed** — a long, fiddly sub-saga
  (secure button for marker emission in combat, marker landing in the log,
  post-combat emission to bypass lockdown, consumable-name blacklist to stop
  self-cast permissiveness). Many small commits = a genuinely hard
  combat-lockdown problem.
- **Dungeon speedrun status frame** (v1.7.x): trash buckets, kill timestamps,
  log-tied timer, multi-variant (LBRS/UBRS/Strat) support, compact rows.
- **Raid auto-log** (v1.7.x): auto `/combatlog` on raid entry, ownership +
  auto-stop, silent mode, Onyxia entry.
- **Practice mode** (v1.7.10): DPS meter without writing a log.
- **Single-target enforcement** (v1.9.x, Epoch-specific): AoE-dummy skip.
- **Polish** (v1.9–v2.0.2): "No player named X" whisper-spam fixes (offline
  target), mob-name typo fixes (Ragetalon→Rage Talon, Scholo Adept, Ghoul
  Ravener), dungeon-frame minimize, and **auto-log defaults flipped OFF** for new
  installs with minimap-menu toggles.
- **Cross-repo hook:** EpogArmory's gear scans feed **epogarmory-web** and are one
  of the stat sources reconciled by **epog-data**.
- **LESSON / open debt:** none of this reached `CLAUDE.md` or `README.md` — the
  flagship is documented only here + git. Folding it into the reference is the top
  debt (see KB §5).

### M3 — EpochSynch: cross-map BG teammate visibility (2026-05, PEBGSync → EpochSynch)
New original addon. 3.3.5 BGs freeze raid-frame data + (x,y) for teammates beyond
the server's ~100-yard visibility range. PEBGSync-3.3.5 v0.1 broadcasts each
player's HP/MP/position over the addon channel (observe-and-relay: sample every
visible raid member, latest-received-wins; tiered ticks 0.5s fast / 2.0s slow;
pipe/comma/semicolon wire format ~5–6 records per ~255-byte message). Renamed to
**EpochSynch v0.2** (new wire prefixes — v0.1 and v0.2 can't talk). **v0.3** added
the in-BG global override of `UnitHealth`/`UnitMana`/`GetPlayerMapPosition` so
_every_ raid-frame addon (default, Grid, HealBot, ShadowedUF) sees fresh data —
with a documented, BG-gated taint cost that uninstalls on BG exit.
- **LESSON:** replacing globals is powerful but taints secure code; gate it to the
  exact window it's needed (in-BG only) and disclose the cost inline.

### M4 — unitscan hardened for Ascension (2026-05, v1.2)
Ascension emits `ADDON_ACTION_BLOCKED` where retail emits
`ADDON_ACTION_FORBIDDEN`; unitscan only listened for FORBIDDEN, so unit detection
silently failed and the red default-UI error leaked (29× in one session).
Fix: treat BLOCKED identically + unregister both on `UIParent` + bail on
`InCombatLockdown()`. **LESSON now in the KB:** any protected-call code must
handle both events on this server.

### M5 — Documentation & triad (2026-07 → 2026-08)
- **2026-07** — `CODE-MAP.md` added, migrating durable facts out of scattered
  cross-project notes.
- **2026-08-03** — standardized `CODE-MAP.md → CodeMap.md` (three-doc triad §5);
  fixed placeholder addon author tags + added the README Credits/Licenses section.
  This DEEP pass then seeded `KnowledgeBase.md` (distilling CLAUDE.md) and this
  journal (distilling git + CHANGELOG).

---

## Open threads (for future entries)

- Fold **EpogArmory** into `CLAUDE.md` + `CodeMap.md` (files, SavedVariables
  schema, the marker round-trip). Currently git-only.
- Confirm the live status of **EpochFixes**' four patches (self-flagged "may be
  server-side").
- Correct the stale `C:\Dev\epog-data` / `C:\Dev\warcraftlogs-epog` paths in
  `CLAUDE.md` "Other Projects" (tree relocated to `C:\Dev\games\wow\`).

_Append new milestones below this line; never rewrite earlier entries._

---

### M6 — CLAUDE.md thinned to env/workflow only (2026-08-03)
`CLAUDE.md` had been the exhaustive reference manual (3.3.5 API table, cross-cutting
patterns, per-addon notes, SavedVariables) with the triad layered on top of it. To
kill the duplication/drift risk, its deep-reference content was MOVED into
`KnowledgeBase.md`: the full API-incompatibility table + code → **KB §2.1**; the
per-addon technical notes + the SavedVariables quick-reference → **KB §9**. The
cross-cutting patterns and the known-issues table were already covered by KB §3/§7
(deleted as duplication, with two stragglers folded into §9: the ItemRack NoBG
zone-misfire guard and the Aux history-string parse format). `CLAUDE.md` now holds
only environment, session workflow, sibling-repo paths, and a pointer into the triad.
`CodeMap.md`'s "where the real docs live" + its internal cross-links were repointed
from `CLAUDE.md` to `KnowledgeBase.md`.
- **Resolves the open thread** "correct the stale `C:\Dev\epog-data` /
  `warcraftlogs-epog` paths": verified on disk and fixed to
  `C:\Dev\games\wow\epog-data`, `…\epogarmory-web`, and `…\epoglogs` (the
  "warcraftlogs-epog" combat-log viewer's real folder is `epoglogs`).
- Edits left in the working tree, not yet committed.
