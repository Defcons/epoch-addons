# Epoch Addons — Knowledge Base

_The distilled, canonical TRUTH about this addon collection: the platform
contract it must obey, the cross-cutting behaviours that bite, and the per-addon
facts that matter. This is the MODEL — not the code index
([`OrientationMap.md`](OrientationMap.md)), not the chronology
([`ResearchJournal.md`](ResearchJournal.md)); deferred work lives in
[`ToDo.md`](ToDo.md), pending human verifications in [`Testing.md`](Testing.md),
per-session change detail in [`CHANGELOG.md`](CHANGELOG.md)._

> **Reference of record:** this KB + `OrientationMap.md`. `CLAUDE.md` is
> env/workflow ONLY (since 2026-08-03); its old deep reference lives HERE — the
> full 3.3.5 API table + code (§2.1), the per-addon notes + SavedVariables
> quick-reference (§9). When docs and code disagree: **code wins, then this KB**;
> correct this file.

_Last verified: 2026-08-20 @ 6f85371 — full pointer re-verification (35 symbol/file
spot-checks, all resolve); §2/§4 deduped against §2.1/§9; EpochSynch facts
consolidated into §9; README gap (§5) re-confirmed on disk._

## How to read this doc

- **[FACT]** — confirmed by code, README, or git history. **[HYP]** — hypothesis
  (confidence % + what settles it). **[ASSUMPTION]** — believed, unverified.
  **[UNKNOWN]** — open question.
- Confidence: 60% likely · 80% strong · 95% almost certain · 100% repeated evidence.

---

## 1. What this collection is

- **[FACT, 100%]** **29 tracked addon folders** ported to / created for **Project
  Epoch** — a WoW private server running the **3.3.5a client (Interface 30300,
  Lua 5.1)** with a _vanilla + TBC talents_ ruleset. Each top-level folder is a
  self-contained addon installed by copying into `Interface/Addons/`. No build
  step. — repo tree, `README.md`. _(Re-counted 2026-08-20: still 29.)_
- **[FACT, 100%]** The repo is an **allowlist**: `.gitignore` default-denies
  `/*` and re-includes only the modified/created addons (`!Addon/`). Everything
  the author didn't touch is deliberately absent, so "not in the tree" ≠ "not
  installed". **Exception:** `Postal/Modules/OpenAll.lua` is tracked but `Postal/`
  has NO allowlist entry — new files under `Postal/` are silently ignored
  (see `ToDo.md`). — `.gitignore`, `git ls-files` (2026-08-20).
- **[FACT, 100%]** Two authorship classes, credited in `README.md`: **new
  originals by Defcon** (BuffWatcher, QuestRewardIcons, DeleteItems, TitanSpeed,
  EpochFixes, AuxTSMBridge, HCBreathBar, FeralAPFix, EpochSynch, EpogArmory,
  TitanPerformance) under GPL-3.0, and **community addons adapted for Epoch**
  (each keeps its original author + license).
- **[FACT, 95%]** Distribution is **per-addon versioned GitHub releases**, some
  **bundled** (ItemRack+ItemRackOptions; pfQuest-epoch+pfQuest-wotlk;
  TSM_Crafting+TSM_AuctionDB ship in one zip). — `README.md`.

## 2. The platform contract (3.3.5a / Lua 5.1) — the deaths that actually bite

_The full incompatibility table + replacement code is **§2.1** (single home —
don't repeat entries elsewhere). The two that bite hardest:_

- **[FACT, 100%]** **`xpcall` silently drops extra args on Lua 5.1** —
  `xpcall(f, handler, ...)` calls `f` with NO args (`self = nil`). Breaks any
  modern Ace3 using variadic xpcall (AceGUI-3.0 v36+). Fix everywhere:
  `pcall(f, ...)` + a manual handler call (applied in ArkInventory).
- **[FACT, 95%]** **Modern texture/atlas/Settings APIs are absent** — the
  dominant hazard when back-porting a retail addon (see FavoriteContacts, ported
  from retail 12.0). Capability-guard (`if tex.SetAtlas then`) or replace per the
  table below.

### 2.1 Full 3.3.5 API incompatibility reference (ported from CLAUDE.md 2026-08-03)

**Missing APIs (modern → 3.3.5 replacement):**

| Modern API | 3.3.5 Replacement / Notes |
|---|---|
| `CreateFromMixins` / `EventRegistry` | Not available (Legion+); rewrite manually |
| `C_Timer.After` / `C_Timer.NewTicker` | Not available (Legion+); see replacement below |
| `Settings.RegisterCanvasLayoutCategory` | Use `InterfaceOptions_AddCategory` |
| `Settings.RegisterAddOnCategory` | Use `InterfaceOptions_AddCategory` |
| `C_AddOns.GetAddOnMetadata` | Use `GetAddOnMetadata` |
| `MenuUtil` / `Menu` / `CreateAnchor` | Use `UIDropDownMenu` |
| `texture:SetAtlas()` | Not available; guard with `if texture.SetAtlas then` |
| `texture:SetColorTexture()` | Not available; use `SetTexture(r, g, b)` |
| `frame:SetMask()` | Not available; guard with `if frame.SetMask then` |
| `frame:GetPortrait()` | Not available; use `frame.portrait` directly |
| `slider:SetObeyStepOnDrag()` | Not available; guard with capability check |
| `WOW_PROJECT_ID` / `WOW_PROJECT_MAINLINE` | Not available |
| `LE_EXPANSION_DRAGONFLIGHT` / `LE_EXPANSION_LEVEL_CURRENT` | Guard with nil check |
| `SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT` | May not exist; use `or 0` |
| `[AllowLoadGameType xxx]` in TOC | Not supported; remove conditionals |
| `SendMailAttachmentButton_OnDropAny` | Not available; guard with nil check |

**Settings panel (3.3.5 pattern):**
```lua
group.frame.name = GetAddOnMetadata(ADDON_NAME, "Title")
InterfaceOptions_AddCategory(group.frame)

-- Open the panel (must call twice for correct tab selection — real 3.3.5 quirk):
InterfaceOptionsFrame_OpenToCategory(frame)
InterfaceOptionsFrame_OpenToCategory(frame)
```

**`C_Timer` replacement** (or Ace3 `ScheduleTimer`/`ScheduleRepeatingTimer` where
the addon already embeds Ace3):
```lua
-- Instead of C_Timer.After(delay, func):
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    func()
end)

-- Instead of C_Timer.NewTicker(interval, func):
frame:SetScript("OnUpdate", func)  -- starts ticker
frame:SetScript("OnUpdate", nil)   -- cancels ticker
```

**`UIDropDownMenu` (context menus):**
```lua
UIDropDownMenu_Initialize(dropdown, initFunc)
UIDropDownMenu_AddButton({ text = "Label", func = callback, notCheckable = true })
ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
```
Use `notCheckable = true` for non-radio menu items.

## 3. Cross-cutting behavioural truths (the ones that cause bugs across addons)

- **[FACT, 100%] Taint is the cardinal rule: hook, never replace.** Raw-replacing
  a Blizzard function in quest/combat code taints protected frames and breaks them
  (dropdowns unreliable in combat, protected calls blocked). Always
  `hooksecurefunc`. pfQuest-wotlk learned this the hard way; it's why EpochFixes
  and pfQuest can coexist.
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
  directly instead of calling Aux (format: §9 AuxTSMBridge).
- **[FACT, 90%] The price-lookup chain is a fixed fallthrough:** Aux (weighted
  median) → TSM (DBMarket) → `GetItemInfo` vendor → 0, each `pcall`-guarded.
  Shared by the wealth/AH tooling; lives in TitanGoldTracker.
- **[FACT, 90%] Ascension emits `ADDON_ACTION_BLOCKED` where retail emits
  `ADDON_ACTION_FORBIDDEN`.** Protection-sensitive addons must treat the two
  identically (unitscan v1.2 had to, or its unit-detection silently failed and the
  red default-UI error leaked). A server-specific divergence worth remembering for
  any new protected-call code.

## 4. Per-addon truth index

_Pure index — one line per addon of note; the facts live in **§9** (deep notes +
SavedVariables) or the named section. Navigation (which folder) is in
[`OrientationMap.md`](OrientationMap.md)._

- **EpogArmory** — the flagship; combat-log/DPS/gear-scan armory → **§5**
  (no §9 notes yet — top doc debt, see `ToDo.md`).
- **Aux-addon** — auction-house engine; module/thread system, temp-table
  allocator (§3) → §9.
- **TitanGoldTracker** — session wealth tracking; hosts the price chain (§3) → §9.
- **AuxTSMBridge** — Aux→TSM price feed via raw history-string parse (the §3
  temp-table workaround) → §9.
- **BuffWatcher** — per-role buff/consume checker → §9.
- **EpochFixes** — four client-bug patches; **self-flagged "not working as
  intended — may be server-side"** → §9; live status queued in `Testing.md`.
- **EpochSynch** — cross-map BG teammate HP/MP/position over the addon channel → §9.
- **pfQuest-epoch / pfQuest-wotlk** — Epoch quest DB overlay → §9.
- **unitscan** — rare scanner; the BLOCKED≡FORBIDDEN fix (§3) → §9.
- **ItemRack(+Options)** — equipment sets; NoBG auto-swap → §9.
- **TSM_Crafting(+AuctionDB)** — crafting queue + vellums; custom JSON parser → §9.
- With §9 notes too: FavoriteContacts, Magnify-WotLK, DeleteItems, HCBreathBar,
  TitanSpeed, ArkInventory.
- Utility/QoL without deep notes (small or lightly-modified): FeralAPFix,
  FishingBuddy, LootAppraiser-3.3.5, NotPlater-3.3.5, PlateBuffs, Postal
  (one tracked file: `Modules/OpenAll.lua`), QuestRewardIcons, TitanPerformance,
  Whats-Training-Epoch.

## 5. EpogArmory — the flagship (and the documentation gap)

- **[FACT, 100%] EpogArmory is by far the most-developed addon here — ~145 of 284
  pre-doc commits (51%), v1.5→v2.0.2, Apr–Jun 2026** — yet it has **no entry in the
  per-addon deep notes (§9) and no row in `README.md`'s catalog** _(re-verified
  2026-08-20)_. This is the collection's biggest doc gap; its history lives only
  in git + `CHANGELOG.md`.
- **[FACT, 90%]** Function, from its commit history: a **combat-log + DPS-meter +
  gear-scan armory** addon. Shipped features include a target-**dummy parse
  validation** module (fires a combat-log marker and verifies the parse landed),
  live DPS display, a **dungeon speedrun status frame** (trash buckets, kill
  timestamps, log-tied timer), **raid auto-log** (auto `/combatlog` on raid entry,
  ownership + auto-stop + silent mode), a **practice mode** (DPS without logging),
  **single-target-only enforcement** (AoE-dummy skip, Epoch-specific), plus
  whisper-spam and mob-name-typo fixes and a minimap menu. As of v2.0.2 the
  auto-log features default OFF for new installs, toggled via the minimap menu.
- **[FACT, 85%] Cross-repo role:** EpogArmory dumps gear scans (`GetItemStats`) to
  its SavedVariables, uploaded to **epogarmory-web**; those scans are one of the
  three stat sources reconciled by **epog-data** (see that repo's KB — "armory
  `GetItemStats` scans"). — `CLAUDE.md` "Other Projects" + epog-data OrientationMap.
- **[UNKNOWN]** EpogArmory's internal architecture (files, SavedVariables schema,
  the marker round-trip mechanism) is not distilled anywhere. Reading its source
  into §9 / `OrientationMap.md` is the top documentation debt (`ToDo.md`).

## 6. Distribution & workflow facts

- **[FACT, 95%]** Session workflow (per `CLAUDE.md`): inline `-- Claude: <desc>`
  comments on changed lines, update `CHANGELOG.md` per session, commit with a
  descriptive message, `git status` before finishing. This is why `CHANGELOG.md`
  is a genuine per-session ledger (165 entries) rather than a release-note stub.
- **[FACT, 100%]** The repo has **two checkouts of the same origin**
  (`Defcons/epoch-addons`): the dev clone `C:\Dev\games\wow\epoch-addons` and the
  **live install checkout** inside the game client (path in `CLAUDE.md`) — the
  game only reads the latter. Doc work happens in the dev clone; live addon edits
  historically happen in the install checkout. Sync via origin, not by copying.
  — verified 2026-08-20 (`git remote -v` in both).
- **[FACT, 95%]** Sibling projects live at `C:\Dev\games\wow\epog-data`,
  `…\epogarmory-web`, `…\epoglogs` (paths verified on disk 2026-08-03 and
  re-verified 2026-08-20).

## 7. Known-fragile / open

- **[OPEN]** EpochFixes self-flagged "not working as intended — may be
  server-side." Its four patches should not be assumed live → `Testing.md`.
- **[OPEN]** EpogArmory undocumented outside git (§5) → `ToDo.md`.
- **[OPEN]** The live install checkout carries uncommitted modifications
  (Aux-addon search UI, TSM_Crafting `CraftingGUI.lua`, pfQuest-epoch toc/docs
  — seen 2026-08-20) and a stale `claude/*` branch → `ToDo.md`.

## 8. Confidence summary

Best-understood (≥95%): the platform contract (§2), the taint rule, the Aux
temp-table crash + workaround, the cross-addon hazards (§3), the distribution
model. Weakest: EpogArmory internals (§5 → `ToDo.md`) and EpochFixes' live patch
status (§7 → `Testing.md`).

---

## 9. Per-addon deep reference & SavedVariables (ported from CLAUDE.md 2026-08-03)

_The detailed per-addon technical notes + the SavedVariables quick-reference.
`(Claude)` marks Defcon/Claude-authored additions to a community addon. The
one-line index in §4 points here; navigation (which folder) is in `OrientationMap.md`._

### Aux-addon
- Module system via `libs/module.lua` with `module` and `include` directives
- Temp-table allocator in `libs/T.lua` for GC optimization (critical — don't bypass)
- Threading via `thread()`, `when()`, `signal()`, `later()` — custom coroutine-like system
- Custom vararg pattern: `vararg-function(arg)` with `arg.n` for argument counts
- **Item key format:** `itemID:suffixID`
- **History key:** `aux.faction[realm|faction].history[item_key]`
- **Decay config (Claude):** `aux.account.history_decay` (default 0.75); exposed via `M.get_decay()` / `M.set_decay(v)`
- **% Hist. Value column (Claude):** in `gui/auction_listing.lua`
- **SavedVariables:** `aux` (scopes: `character`, `faction`, `realm`, `account`), `aux_scale`, `aux_items`, `aux_item_ids`, etc.

### TitanGoldTracker
- Ace3-based (AceAddon, AceHook, AceTimer)
- 1-second bar update via Ace3 `ScheduleRepeatingTimer` (no C_Timer)
- UIDropDownMenu for character selector dropdown
- **Session item wealth tracking (Claude additions):**
  - `GT_PriceCache[item_key]` — session-only copper/item from Aux or TSM
  - `GT_QualCache[link]` — item quality (0–6)
  - `GT_TradeableCache[itemID]` — BoP detection via GameTooltip:SetHyperlink
  - `GT_ItemValCache[charIndex]` — bags+bank total copper
  - `GT_AHValCache[charIndex]` — own AH listings total copper
  - `GT_SessAHBase` — snapshot of (bags+AH) at session start
  - `GT_SessMailedVal` — cumulative mailed value this session
  - `GT_SessBagAtMail` — bag value at MAIL_SHOW (to compute outgoing)
- **Events:** `PLAYER_MONEY`, `BAG_UPDATE` (debounced 0.5s), `BANKFRAME_OPENED`, `AUCTION_OWNED_LIST_UPDATE`, `MAIL_SHOW`, `MAIL_SEND_SUCCESS`
- **Price chain:** Aux weighted median → TSM DBMarket → `GetItemInfo` vendor → 0
- **SavedVariables:** `GoldArray` keyed by `realm|charname`

### EpochFixes *(status: not working as intended — issues may be server-side; see Testing.md)*
Four targeted client bug patches:
1. **Spellbook crash** — wraps `SpellBookFrameTabButton2:GetScript("OnEnter")` in `pcall()`
2. **Quest abandon wrong quest** — hooks `QuestLogAbandonButton:OnClick()` to save title+index; hooks popup `OnAccept()` to restore selection by title before `AbandonQuest()` fires
3. **Quest reward tooltips** — hooks each `QuestInfoItem[1-6]:OnEnter()` to force `GameTooltip:SetOwner()` before `SetQuestItem()`, undoing pfQuest/Leatrix anchor theft
4. **Inspect tooltip cache expiry** — caches all 19 slot links on `INSPECT_READY`; `OnEnter()` hooks fall back to `SetHyperlink(cachedLink)` when live link is nil
- **Pattern:** Separate frames for `PLAYER_LOGIN` and event handlers to avoid script clobbering.
- Debug slash: `/epochdebug`

### EpochSynch (was PEBGSync-3.3.5)
- 3.3.5 BGs freeze raid-frame data + (x,y) for teammates beyond ~100-yard server
  visibility; EpochSynch broadcasts each player's HP/MP/position over the addon
  channel (observe-and-relay, latest-received-wins; wire details in the Journal M3)
- v0.1↔v0.2 wire prefixes are INCOMPATIBLE (rename PEBGSync→EpochSynch changed them)
- **v0.3 in-BG global override (deliberate taint trade):** overrides
  `UnitHealth`/`UnitMana`/`GetPlayerMapPosition` inside BGs so _every_ raid-frame
  addon (default, Grid, HealBot, ShadowedUF) sees fresh data. Cost (disclosed):
  raid-frame right-click dropdown unreliable in combat inside BGs. The override
  uninstalls on BG exit, so out-of-BG play is taint-free. [FACT, 90%]

### pfQuest-epoch
- Depends on `pfQuest-wotlk` (loaded after via `depend pfQuest-wotlk` in TOC)
- Removes unavailable Epoch content by setting entries to `{}`:
  ```lua
  pfDB["units"]["data-epoch"][15174] = {}  -- removes NPC
  pfDB["quests"]["data-epoch"][8369] = {}  -- removes quest
  ```
- Removals cover: Silithus NPCs, TBC quest NPCs, PvP quests not yet on server
- `patchtable.lua` patches quest objectives/rewards/level ranges for Epoch-specific changes

### pfQuest-wotlk
- Database: `pfDB["quests"]`, `pfDB["units"]`, `pfDB["objects"]`, `pfDB["items"]`
- Uses `hooksecurefunc('QuestLog_Update', ...)` (taint-safe, required for EpochFixes compatibility)
- **Minimap range-limited icons (Claude):** only draws icons within encounter range to reduce clutter

### unitscan
- LibCompat-1.0 backport embedded for 3.3.5 compatibility
- **QuickDispatch (Claude):** `pcall()`-based dispatch wraps scan callbacks to prevent crashes from bad data
- Scans nearby units via `UnitName()` + database lookup on `OnUpdate`

### ArkInventory
- Ace3 xpcall Lua 5.1 fix applied to event dispatchers:
  ```lua
  local ok, err = pcall(func, arg1, arg2)
  if not ok then handler(err) end
  ```
- Core files: `ArkInventory.lua`, `ArkInventoryStorage.lua`, `ArkInventoryRules.lua`, `ArkInventorySearch.lua`

### ItemRack / ItemRackOptions
- **NoBG flag (Claude):** `ItemRackUser[setName].NoBG = true`
- On `ZONE_CHANGED_NEW_AREA`: if in BG/Arena and current set has NoBG, auto-switch to default gear
- ItemRackOptions is LoadOnDemand — opens on first `/itemrack` command
- NoBG checkbox added to Sets panel in ItemRackOptions
- Known issue: zone change can misfire — guard checks current_set before applying.

### FavoriteContacts (ported from retail 12.0)
- Removed: `CreateFromMixins`, `EventRegistry`, `Settings` API, modern atlas icons
- Manual callback tables replace EventRegistry: `RegisterLoginCallback()`, `RegisterLoadUICallback()`
- `parentKey` pattern manually implemented
- MSA-DropDownMenu-1.0 (LibStub) for right-click context menus
- Contact format: `{recipient, icon, note}` stored in `FavoriteContactsSettings.contacts[index]`

### AuxTSMBridge
- Reads raw aux history strings directly (avoids aux temp-table allocator)
- **Aux history string format:** `next_push#daily_min_buyout#val@time;val@time;...` — split on `#` (first two = next_push, daily_min; rest = data points); each point via `gmatch("([^;]+)", segment)` then split on `@` → value, timestamp
- Writes to TSM AuctionDB via `adbModule:DecodeItemData()` / `EncodeItemData()`
- Registers two TSM price sources: `AuxMarket`, `AuxMinBuyout`
- Rate-limited: syncs at most every 12 hours (`AuxTSMBridgeDB.lastSyncTime`)
- Guard: `d.quantity > 0` before encoding (nil quantity crashes TSM)
- Slash: `/axtsm sync` (force), `/axtsm status`

### TradeSkillMaster_AuctionDB
- Custom JSON parser (no LibJSON on 3.3.5)
- `decodeScans()` wrapped in `pcall()` — corrupt scan data no longer crashes
- Faction data merge: guards against nil faction tables
- Provides `DBMarket` and `DBMinBuyout` price sources to TSM formulas

### TradeSkillMaster_Crafting
- **Vellum support (Claude):** `Modules/VellumInfo.lua` maps enchantments → vellum item IDs; `CheapestVellum` logic picks cheapest available; DB migration converts existing recipes
- Scrap-conversion recipes excluded from intermediate crafting

### BuffWatcher
- Per-role buff/consume checker with talent-based spec detection
- 4 roles: Tank, Healer, Melee, Ranged — each with independent buff entry lists
- Spec detection: `GetTalentTabInfo()` for player, `NotifyInspect()` queue for raid members
- Inspect queue: one-at-a-time with 3s timeout, fallback to `CLASS_DEFAULT_ROLE`
- `BW.SPEC_ROLE_MAP[classFile][tabIndex]` maps talent tab → role
- `BuffWatcherDB.specRoles[classFile][tabIndex]` stores user overrides
- Config UI: UIDropDownMenu role selector, per-role entry editor, spec override panel
- Status frame shows Role column; Export TSV includes Role + per-role label applicability
- Slash: `/bw`, `/bw config`, `/bw check`, `/bw export`, `/bw inspect`, `/bw help`
- Migration: reads old `BuffWatcher2DB` if present
- **TOC load order:** `BuffWatcher_Data.lua` → `BuffWatcher.lua` → `BuffWatcher_Config.lua`
- **Cross-file contracts:**
  - `BW` table defined in Data.lua; extended in BuffWatcher.lua and Config.lua
  - `BW.ROLES`, `BW.SPEC_ROLE_MAP`, `BW.DefaultRoleEntries`, `BW.ClassColors`, `BW.RoleColors` — all in Data.lua
  - `BW.inspectResults[guid]` — cached `{ classFile, role }` per inspected player
  - `BuffWatcherDB.roles[role].entries` — per-role buff entry arrays
  - `BuffWatcherDB.specRoles` — optional override table
- **SavedVariables:** `BuffWatcherDB` → `{ roles = { Tank = { entries = {...} }, ... }, specRoles = {}, buttonPos = {} }`

### DeleteItems
- Three named deletion lists (itemID-keyed, account-wide)
- Junk scanner: bags below `DIData.junkThreshold` copper, excluding `DIData.junkIgnore`
- No suffix/enchant differentiation — item ID only

### HCBreathBar
- Hides original breath bar (`SetAlpha(0)`), renders custom bar
- Sound alert below 20s: `PlaySoundFile("Sound\\Interface\\AlarmClockWarning1.wav")`
- Alert rate doubles below 10s
- Combat overlay warns against using spacebar to surface

### TitanSpeed
- Updates every 0.2s via `OnUpdate`
- Speed % = `GetUnitSpeed("player") / 7 * 100` (7 yards/sec = 100%)
- `SPEED_BUFF_INFO` table for buff name → bonus% mapping (English only)

### Magnify-Wotlk
- Zoom range: 1.0–4.0x (map), 1.0–10.0x (minimap), step 0.2 / 0.1
- `MagnifyOptions.enablePersistZoom`: remembers pan/zoom per zone
- Resizes quest POI buttons to match zoom via `ResizeQuestPOIs()`
- Mapster compatibility: disables Mapster POI handler if present

### SavedVariables quick reference

| Addon | Variable | Key Structure |
|---|---|---|
| Aux-addon | `aux` | `{character, faction, realm, account}` scopes |
| TitanGoldTracker | `GoldArray` | `[realm\|charname]` → gold + session data |
| AuxTSMBridge | `AuxTSMBridgeDB` | `{lastSyncTime}` |
| DeleteItems | `DIData` | `{lists, listNames, junkThreshold, junkIgnore, activeList}` |
| Magnify-Wotlk | `MagnifyOptions` | `{enablePersistZoom}` |
| FavoriteContacts | `FavoriteContactsSettings` | `{contacts[], columnCount, rowCount, enabled}` |
| ItemRack | `ItemRackUser` | `[charname]` → `{currentSet, NoBG}` |
| pfQuest-wotlk | `pfQuest_config` | Per-character quest log state, colors |
