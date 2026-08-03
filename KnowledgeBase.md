# Epoch Addons — Knowledge Base

_The distilled, canonical TRUTH about this addon collection as a working system:
the platform contract it must obey, the cross-cutting behaviours that bite, and
the per-addon facts that matter. This is the MODEL — not the code index
([`CodeMap.md`](CodeMap.md)) and not the chronology
([`ResearchJournal.md`](ResearchJournal.md))._

_The triad: **CodeMap = the machine · KnowledgeBase = the model ·
ResearchJournal = the history.**_

> **Reconcile note — this KB does NOT replace [`CLAUDE.md`](CLAUDE.md).**
> `CLAUDE.md` is the exhaustive REFERENCE MANUAL (the full 3.3.5-API-death
> table, every cross-cutting pattern with code, per-addon notes, the
> SavedVariables quick-reference). This KB is the thin, tagged MODEL layer that
> states _what is true and why it bites_ and points INTO `CLAUDE.md` for the
> detail. When they disagree, the code wins, then `CLAUDE.md`; correct this file.
> Per-session change detail lives in [`CHANGELOG.md`](CHANGELOG.md) (the Journal
> summarises it).

_Last verified: 2026-08-03 @ 8223a48 (master) — seeded from CLAUDE.md + README +
git history (284 commits, 29 tracked addons) as the DEEP-pass model layer._

## How to read this doc

- **[FACT]** — confirmed by code, CLAUDE.md, README, or git history.
- **[HYP]** — hypothesis; carries a confidence % and what would settle it.
- **[ASSUMPTION]** — believed, unverified.
- **[UNKNOWN]** — open question.

Confidence: 60% likely · 80% strong · 95% almost certain · 100% repeated evidence.

---

## 1. What this collection is

- **[FACT, 100%]** **29 tracked addon folders** ported to / created for **Project
  Epoch** — a WoW private server running the **3.3.5a client (Interface 30300,
  Lua 5.1)** with a _vanilla + TBC talents_ ruleset. Each top-level folder is a
  self-contained addon installed by copying into `Interface/Addons/`. There is no
  build step. — repo tree, `README.md`.
- **[FACT, 100%]** The repo is an **allowlist**: `.gitignore` default-denies
  `/*` and re-includes only the modified/created addons (`!Addon/`). Everything
  the author didn't touch is deliberately absent, so "not in the tree" ≠ "not
  installed". — `.gitignore`.
- **[FACT, 100%]** Two authorship classes, credited in `README.md`: **new
  originals by Defcon** (BuffWatcher, QuestRewardIcons, DeleteItems, TitanSpeed,
  EpochFixes, AuxTSMBridge, HCBreathBar, FeralAPFix, EpochSynch, EpogArmory,
  TitanPerformance) under GPL-3.0, and **community addons adapted for Epoch**
  (each keeps its original author + license).
- **[FACT, 95%]** Distribution is **per-addon versioned GitHub releases**, some
  **bundled** (ItemRack+ItemRackOptions; pfQuest-epoch+pfQuest-wotlk;
  TSM_Crafting+TSM_AuctionDB ship in one zip). — `README.md`.

## 2. The platform contract (3.3.5a / Lua 5.1) — the deaths that actually bite

_Full incompatibility table in [`CLAUDE.md` §"Critical WoW 3.3.5 API
Incompatibilities"]. The load-bearing ones every addon here has had to route
around:_

- **[FACT, 100%]** **`xpcall` silently drops extra args on Lua 5.1** —
  `xpcall(f, handler, ...)` calls `f` with NO args (`self = nil`). This breaks any
  modern Ace3 that uses variadic xpcall (AceGUI-3.0 v36+). Fix everywhere:
  `pcall(f, ...)` + a manual handler call (applied in ArkInventory). — `CLAUDE.md`.
- **[FACT, 100%]** **`C_Timer` does not exist** (Legion+). Replacement is a
  `CreateFrame("Frame")` + `OnUpdate` one-shot / ticker, or Ace3
  `ScheduleTimer`/`ScheduleRepeatingTimer` where the addon already embeds Ace3.
- **[FACT, 100%]** **The modern `Settings.*` canvas API is absent** — use
  `InterfaceOptions_AddCategory`, and `InterfaceOptionsFrame_OpenToCategory`
  **must be called twice** to select the right tab (a real 3.3.5 quirk).
- **[FACT, 95%]** **Texture/atlas modern methods are missing** — `SetAtlas`,
  `SetColorTexture`, `SetMask`, `SetObeyStepOnDrag`, `GetPortrait` etc. must be
  capability-guarded (`if tex.SetAtlas then`) or replaced with the 3.3.5 call.
  This is the dominant hazard when back-porting a retail addon (see
  FavoriteContacts, ported from retail 12.0).

## 3. Cross-cutting behavioural truths (the ones that cause bugs across addons)

- **[FACT, 100%] Taint is the cardinal rule: hook, never replace.** Raw-replacing
  a Blizzard function in quest/combat code taints protected frames and breaks them
  (dropdowns unreliable in combat, protected calls blocked). Always
  `hooksecurefunc`. pfQuest-wotlk learned this the hard way; it's why EpochFixes
  and pfQuest can coexist. — `CLAUDE.md`.
- **[FACT, 95%] `GameTooltip` ownership gets stolen mid-frame** by any addon
  calling `SetHyperlink` on `OnUpdate` (pfQuest scanner, Leatrix). Defence: always
  `SetOwner(button, "ANCHOR_RIGHT")` immediately before use, and cache links as a
  fallback (EpochFixes caches all 19 inspect slots on `INSPECT_READY` because live
  links expire after ~10–15s).
- **[FACT, 95%] Quest-log selection drifts** — `QUEST_LOG_UPDATE` can fire between
  "click abandon" and "confirm", changing `GetQuestLogSelection()`. EpochFixes
  captures title+index at click and re-selects by **title** (robust) before
  `AbandonQuest()`.
- **[FACT, 95%] `BAG_UPDATE` fires in floods** — must be debounced (~0.5s Ace3
  timer) or bag/wealth scans thrash. — TitanGoldTracker.
- **[FACT, 95%] The Aux temp-table allocator is a crash trap.** Aux's `libs/T.lua`
  GC-optimised temp tables mean calling Aux's history/scan functions in an
  external mass-parse loop exhausts the heap and crashes. AuxTSMBridge exists
  specifically to route around this — it parses the **raw aux history string**
  (`next_push#daily_min#val@time;...`) directly instead of calling Aux.
- **[FACT, 90%] The price-lookup chain is a fixed fallthrough:** Aux (weighted
  median) → TSM (DBMarket) → `GetItemInfo` vendor → 0, each `pcall`-guarded. Shared
  by the wealth/AH tooling (TitanGoldTracker). — `CLAUDE.md`.
- **[FACT, 90%] Ascension emits `ADDON_ACTION_BLOCKED` where retail emits
  `ADDON_ACTION_FORBIDDEN`.** Protection-sensitive addons must treat the two
  identically (unitscan v1.2 had to, or its unit-detection silently failed and the
  red default-UI error leaked). A server-specific divergence worth remembering for
  any new protected-call code.

## 4. Per-addon truth index

_One durable line each; deep per-addon notes + the SavedVariables quick-reference
table live in [`CLAUDE.md`]. Navigation (which folder) is in [`CodeMap.md`]._

- **EpogArmory** — the flagship; combat-log/DPS + gear-scan armory addon. See §5.
- **Aux-addon** — auction house; custom module/thread system + temp-table
  allocator (`libs/T.lua`, don't bypass). Item key `itemID:suffixID`. Defcon adds:
  history-decay knob, "% Hist. Value" column.
- **TitanGoldTracker** — session wealth (bags+bank+own-AH+mail), BoP detection via
  tooltip scan, cross-faction display; the price chain lives here.
- **AuxTSMBridge** — feeds Aux prices into TSM by direct history-string parse
  (the temp-table workaround); rate-limited to ≤ every 12h.
- **BuffWatcher** — per-role (Tank/Healer/Melee/Ranged) buff/consume checker;
  role from `GetTalentTabInfo` (self) + `NotifyInspect` queue (raid). Data/logic/
  config split across three files with an explicit `BW.*` cross-file contract.
- **EpochFixes** — four client-bug patches (spellbook crash, quest-abandon,
  quest-reward tooltips, inspect-cache expiry). **Flagged in CLAUDE.md as "not
  working as intended — may be server-side"** — treat its fixes as provisional.
- **EpochSynch** (was PEBGSync-3.3.5) — cross-map BG teammate HP/MP/position via
  the addon channel; v0.3 adds an in-BG global override of `UnitHealth`/`UnitMana`/
  `GetPlayerMapPosition` for universal raid-frame compat (documented taint cost).
- **pfQuest-epoch / pfQuest-wotlk** — Epoch quest DB overlay (removes unavailable
  content by setting entries to `{}`); taint-safe `hooksecurefunc('QuestLog_Update')`.
- **unitscan** — rare scanner; the BLOCKED-vs-FORBIDDEN fix (§3) + `pcall` dispatch.
- **ItemRack(+Options)** — equipment sets; NoBG flag auto-swaps out of BG/Arena gear.
- **TSM_Crafting(+AuctionDB)** — crafting queue + vellum support; custom JSON parser
  (no LibJSON on 3.3.5), `pcall`-guarded scan decode.
- Utility/QoL: FavoriteContacts (retail-12.0 back-port), Magnify-WotLK (map zoom),
  HCBreathBar (hardcore breath alarm), TitanSpeed, TitanPerformance, DeleteItems,
  QuestRewardIcons, NotPlater-3.3.5, Whats-Training-Epoch, FeralAPFix,
  LootAppraiser-3.3.5, PlateBuffs, FishingBuddy, Postal.

## 5. EpogArmory — the flagship (and the documentation gap)

- **[FACT, 100%] EpogArmory is by far the most-developed addon here — 145 of 284
  commits (51%), v1.5→v2.0.2, Apr–Jun 2026** — yet it has **no entry in
  `CLAUDE.md`'s per-addon notes and no row in `README.md`'s catalog.** This is the
  collection's biggest doc gap; its history lives only in git + `CHANGELOG.md`.
  _(git-verified; see the Journal.)_
- **[FACT, 90%]** Function, from its commit history: a **combat-log + DPS-meter +
  gear-scan armory** addon. Shipped features include a target-**dummy parse
  validation** module (fires a combat-log marker and verifies the parse landed),
  live DPS display, a **dungeon speedrun status frame** (trash buckets, kill
  timestamps, log-tied timer), **raid auto-log** (auto `/combatlog` on raid entry,
  ownership + auto-stop + silent mode), a **practice mode** (DPS without logging),
  **single-target-only enforcement** (AoE-dummy skip, Epoch-specific), plus
  whisper-spam and mob-name-typo fixes and a minimap menu.
- **[FACT, 85%] Cross-repo role:** EpogArmory dumps gear scans (`GetItemStats`) to
  its SavedVariables, uploaded to **epogarmory-web**; those scans are one of the
  three stat sources reconciled by **epog-data** (see that repo's KB — "armory
  `GetItemStats` scans"). — `CLAUDE.md` "Other Projects" + epog-data CodeMap.
- **[UNKNOWN]** EpogArmory's internal architecture (files, SavedVariables schema,
  the marker round-trip mechanism) is not distilled anywhere. Reading its source
  into CLAUDE.md/CodeMap is the top documentation debt.

## 6. Distribution & workflow facts

- **[FACT, 95%]** Session workflow (per `CLAUDE.md`): inline `-- Claude: <desc>`
  comments on changed lines, update `CHANGELOG.md` per session, commit with a
  descriptive message, `git status` before finishing. This is why `CHANGELOG.md`
  is a genuine per-session ledger (165 entries) rather than a release-note stub.
- **[FACT, 90%]** Cross-references in `CLAUDE.md` "Other Projects" carry **stale
  absolute paths** (`C:\Dev\epog-data`, `C:\Dev\warcraftlogs-epog`). The WoW tree
  relocated to `C:\Dev\games\wow\` (epog-data's CodeMap confirms). Trust the
  relocated paths.

## 7. Known-fragile / open

- **[OPEN]** EpochFixes self-flagged "not working as intended — may be
  server-side." Its four patches should not be assumed live.
- **[OPEN]** EpogArmory undocumented outside git (§5).
- **[FACT, 90%]** EpochSynch's in-BG global override propagates a small, disclosed
  taint (raid-frame right-click dropdown unreliable in combat inside BGs); it
  uninstalls on BG exit so out-of-BG play is taint-free. A deliberate trade, not a
  bug.

## 8. Confidence summary

Best-understood (≥95%): the platform contract (the API deaths), the taint rule,
the Aux temp-table crash + workaround, the cross-addon behavioural hazards, the
distribution model — all cross-checked against code + CLAUDE.md. Weakest (≤85% /
UNKNOWN): EpogArmory's internals and SavedVariables schema, and the current live
status of EpochFixes' four patches. Those are the priority for the next reading
pass — and the reason `CLAUDE.md` (not this file) remains the reference of record
until EpogArmory is folded into it.
