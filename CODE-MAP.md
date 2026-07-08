# Code Map — epoch-addons

<!--
  Thin, pointer-based index. Read first, update after changes.
  Anchor to SYMBOL names, never line numbers. Only expensive-to-rediscover facts.
-->

_Last verified: 2026-07-08 @ e52873a (master) — by Opus 4.8 (memory migration)_

## What this is
20+ WoW addons ported to / created for **Project Epoch** (vanilla + TBC talents, 3.3.5a client, Interface 30300, Lua 5.1). Each addon is a self-contained folder installed by copying into `Interface/Addons/`. Repo tracks only modified/created addons — everything else is excluded via `.gitignore` (default-deny `/*` + explicit `!Addon/` allowlist).

## Where the real docs live (don't duplicate here)
- **`CLAUDE.md`** — the authoritative deep reference: 3.3.5 API incompatibilities (xpcall/C_Timer/Settings), cross-cutting patterns (tooltip ownership, quest-log drift, price chain, BAG_UPDATE debounce), per-addon technical notes, and a SavedVariables quick-reference table. Read it before touching any tracked addon.
- **`README.md`** — user-facing addon catalog (new vs ported), bundle groupings, credits/licenses.
- **`CHANGELOG.md`** — per-session change log (append at end of each session per CLAUDE.md workflow).

## Subsystems (where things live)
Each top-level folder is one addon. High-value ones (see CLAUDE.md for full notes):
- **Aux-addon** → auction house; custom module/thread system in `libs/`, temp-table allocator `libs/T.lua` (don't bypass), item key `itemID:suffixID`.
- **TitanGoldTracker** → gold/wealth tracking; `GT_*Cache` session tables, price chain Aux→TSM→vendor.
- **AuxTSMBridge** → feeds Aux prices into TSM by parsing raw aux history strings directly (avoids the temp-table allocator crash).
- **BuffWatcher** → per-role buff/consume checker; `BW.*` tables in `BuffWatcher_Data.lua`, spec→role via `GetTalentTabInfo`.
- **EpochFixes / FeralAPFix** → client-bug patches (spellbook, quest abandon, tooltip theft, inspect cache).
- Others: ArkInventory, ItemRack(+Options), pfQuest-epoch(+wotlk), unitscan, TSM_Crafting(+AuctionDB), FavoriteContacts, Magnify-WotLK, NotPlater-3.3.5, Whats-Training-Epoch, DeleteItems, HCBreathBar, TitanSpeed, TitanPerformance, QuestRewardIcons, FishingBuddy, PlateBuffs, EpochSynch, EpogArmory, LootAppraiser-3.3.5.

### EpochSimData (ESD) — sim-calibration capture addon (NOT in this repo)
Multi-class combat-data capture addon feeding sim calibration. **`.gitignore`'d from this repo** (calibration-only, not distributed) — code lives ONLY at the install path, edits are local, `/reload` in WoW to pick up changes.
- **Install path**: `C:\Private\Games\Ascension Launcher\resources\epoch_live\Interface\AddOns\EpochSimData\`
- **Files**: `EpochSimData.toc` (Interface 30300), `EpochSimData.lua` (single file, ~950 lines), `parse_saved.py` (pure-Python Lua-table → JSON, no deps), `README.md` (class coverage matrix).
- **SavedVariables**: `EpochSimDataDB` (per-account, settings) + `EpochSimDataCharDB` (per-character, nearly all data — combat is character-specific).
- **Slash commands**: `/esd` (help/status), `/esd snap <label>` (manual snapshot), `/esd clear` (wipe char DB, use after OOM), `/esd auto` (toggle idle-tick auto-snapshots; combat events always captured).
- Supports Hunter/Warrior/Rogue/Mage/Druid/Shaman; class-specific data flows through generic capture and is sliced per-class by `identity.class` in the parser. Friends on other classes can contribute by sharing their SavedVariables file.

## Invariants & gotchas
- **ring-buffer FIFO caps**: every event buffer is capped so the file can't grow unbounded. (ESD) latest documented caps: `snapshots` 2000, `damageEvents` 15000, `auraEvents` 12000, `castEvents` 12000, `powerEvents` 8000, `energizeEvents` 8000 (~21 MB ceiling). (Earlier v1.2 caps were much lower: 500/5000/2000/…) Verify current caps in `EpochSimData.lua` before relying on numbers.
- **lua-block-too-big**: the 3.3.5 client SavedVariables serializer dies if any single table exceeds the Lua parser's per-chunk constant limit (`MAXARG_Bx` = 262143 constants). Burned in 2026-05 with a 33 MB file. **Fix (ESD architecture)**: heavy state (`gear`, `talents`, `petTalents`, `totems`) is stored ONCE at TOP level, NOT embedded per snapshot. Combine with the ring-buffer caps to stay under the limit. Any addon writing large SavedVariables must respect this.
- **heavy-vs-light snapshot split** (ESD): `isHeavySnapshot(label)` decides weight by label prefix. Heavy (~25 KB) includes gear/talents/pet/totems, taken on manual/combat-start/combat-end/equip/inv/talent/spec/stance/totem/pre-bw/post-bw. Light (~5 KB) is just buffs + effective stats, taken on every in-combat aura event. Keeps bursty raid combat from bloating the file with redundant gear scans.
- **ESD snapshot triggers** are a coarse schedule + a whitelist of "snapshot-worthy" auras (racials, trinket procs, raid CDs, raid buffs), with a per-aura 1.0s debounce and a 5s auto-tick that only fires if the buff-hash changed.
- **ensureTables()** (ESD): called at every entry point; recreates missing DB fields so schema migrations (new event type) don't break old files.
- **xpcall drops varargs on Lua 5.1** — breaks Ace3 AceGUI variadic xpcall; replace with `pcall` + manual handler (see CLAUDE.md; applied in ArkInventory).
- **Never raw-replace Blizzard functions** in quest/combat code — taint breaks protected frames; use `hooksecurefunc` (pfQuest lesson).

## Contracts / capture fields
- Every ESD event (`damageEvents`, `castEvents`, `auraEvents`, `powerEvents`, `energizeEvents`) carries a `snapshotIndex` pointing at the most recent snapshot, so `parse_saved.py` can correlate event ↔ player state ("what was RAP when this hit fired?").
- ESD damage events record partial-mitigation fields `resisted`, `blocked`, `absorbed` (added v2.4) in addition to `amount` — before this, partial blocks looked like reduced normal hits.

## Known landmines / deferred
- **ESD `ranged_damage_min/max`** snapshot fields are UNRELIABLE (addon bug, don't match displayed weapon damage) — cross-check against gear info.
- **ESD damage events with `amount=0`** (e.g. Lightning Breath) are MISSES, not full resists — the addon doesn't route MISSED events to a separate stream.
- **EpochFixes** is marked "not working as intended — issues may be server-side" in CLAUDE.md.
