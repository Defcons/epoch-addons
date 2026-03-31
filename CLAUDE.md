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

## Critical WoW 3.3.5 API Incompatibilities

### xpcall does NOT support extra arguments (Lua 5.1)

`xpcall(func, handler, ...)` silently drops extra args — `func` is called with no args (`self = nil`).

**Fix:** Replace with `pcall(func, ...)` + manual error handler call.

This breaks any modern Ace3 library that uses variadic xpcall (AceGUI-3.0 v36+).

### Missing APIs

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

### Settings Panel (3.3.5 pattern)

```lua
group.frame.name = GetAddOnMetadata(ADDON_NAME, "Title")
InterfaceOptions_AddCategory(group.frame)

-- Open the panel (must call twice for correct tab selection):
InterfaceOptionsFrame_OpenToCategory(frame)
InterfaceOptionsFrame_OpenToCategory(frame)
```

### C_Timer replacement

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

### UIDropDownMenu (context menus)

```lua
UIDropDownMenu_Initialize(dropdown, initFunc)
UIDropDownMenu_AddButton({ text = "Label", func = callback, notCheckable = true })
ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
```

Use `notCheckable = true` for non-radio menu items.

---

## Cross-Cutting Patterns

### Tooltip Ownership Management

`GameTooltip` ownership can be stolen mid-frame by pfQuest scanner, Leatrix, or any addon calling `SetHyperlink` on OnUpdate. Fixes:
- Always call `GameTooltip:SetOwner(button, "ANCHOR_RIGHT")` explicitly before use
- Cache item links on `INSPECT_READY` as fallback (EpochFixes)
- Guard nil links in `SetHyperlink` (FeralAPFix)

### Quest Log Drift

`QUEST_LOG_UPDATE` can fire and change `GetQuestLogSelection()` between "click abandon" and "confirm". EpochFixes solution: capture `savedAbandonTitle` + `savedAbandonIndex` on button click, then search by title (robust) before calling `AbandonQuest()`.

### Price Lookup Chain (used in TitanGoldTracker)

```lua
-- Aux → TSM → vendor → 0
-- pcall each source, fall through on nil/error
```

### BAG_UPDATE Debouncing

`BAG_UPDATE` fires in floods. Use Ace3 timer: `CancelTimer()` + `ScheduleTimer(0.5, ...)`.

### Aux Temp-Table System

Aux uses `libs/T.lua` for GC-efficient temp tables. **Do not call aux's history/scan functions in mass-parse loops from external code** — crashes on heap exhaustion. AuxTSMBridge avoids this by parsing the raw history string directly.

### Aux History String Format

```
"next_push#daily_min_buyout#val@time;val@time;..."
```
- Split on `#` (first 2 = next_push, daily_min; rest = data points)
- Data points: `gmatch("([^;]+)", segment)` → split on `@` → value, timestamp

### hooksecurefunc vs Raw Replace

Always use `hooksecurefunc()` when hooking Blizzard functions in quest/combat code. Raw replacement causes taint that breaks protected frames. (pfQuest-wotlk learned this the hard way.)

---

## Known Issues & Fragile Areas

| Area | Issue | Fix / Mitigation |
|---|---|---|
| Aux temp-table | Mass external parse crashes | AuxTSMBridge uses direct string parsing |
| GameTooltip | Stolen by concurrent addon | Explicit SetOwner() + nil link guard |
| Quest log abandon | Index drifts on QUEST_LOG_UPDATE | EpochFixes saves title+index at click time |
| Ace3 xpcall | Lua 5.1 drops variadic args silently | pcall + manual error handler (ArkInventory) |
| Inspect cache | Item links expire after ~10–15s | EpochFixes caches all 19 slots on INSPECT_READY |
| ItemRack NoBG | Zone change can misfire | Guard checks current_set before applying |
| TSM encoding | nil quantity crashes tooltip | Guard `d.quantity > 0` before encoding |
| pfQuest taint | Raw QuestLog_Update replace taints UI | Use hooksecurefunc() instead |

---

## Addon Technical Notes

### Aux-addon

- Module system via `libs/module.lua` with `module` and `include` directives
- Temp-table allocator in `libs/T.lua` for GC optimization (critical — don't bypass)
- Threading via `thread()`, `when()`, `signal()`, `later()` — custom coroutine-like system
- Custom vararg pattern: `vararg-function(arg)` with `arg.n` for argument counts
- **Item key format:** `itemID:suffixID`
- **History key:** `aux.faction[realm|faction].history[item_key]`
- **Decay config (Claude):** `aux.account.history_decay` (default 0.75); exposed via `M.get_decay()` / `M.set_decay(v)`
- **% Hist. Value column (Claude):** in `gui/auction_listing.lua`

**SavedVariables:** `aux` (scopes: `character`, `faction`, `realm`, `account`), `aux_scale`, `aux_items`, `aux_item_ids`, etc.

---

### TitanGoldTracker

- Ace3-based (AceAddon, AceHook, AceTimer)
- 1-second bar update via Ace3 `ScheduleRepeatingTimer` (no C_Timer)
- UIDropDownMenu for character selector dropdown

**Session item wealth tracking (Claude additions):**
- `GT_PriceCache[item_key]` — session-only copper/item from Aux or TSM
- `GT_QualCache[link]` — item quality (0–6)
- `GT_TradeableCache[itemID]` — BoP detection via GameTooltip:SetHyperlink
- `GT_ItemValCache[charIndex]` — bags+bank total copper
- `GT_AHValCache[charIndex]` — own AH listings total copper
- `GT_SessAHBase` — snapshot of (bags+AH) at session start
- `GT_SessMailedVal` — cumulative mailed value this session
- `GT_SessBagAtMail` — bag value at MAIL_SHOW (to compute outgoing)

**Events:** `PLAYER_MONEY`, `BAG_UPDATE` (debounced 0.5s), `BANKFRAME_OPENED`, `AUCTION_OWNED_LIST_UPDATE`, `MAIL_SHOW`, `MAIL_SEND_SUCCESS`

**Price chain:** Aux weighted median → TSM DBMarket → `GetItemInfo` vendor → 0

**SavedVariables:** `GoldArray` keyed by `realm|charname`

---

### EpochFixes *(status: not working as intended — issues may be server-side)*

Four targeted client bug patches:

1. **Spellbook crash** — wraps `SpellBookFrameTabButton2:GetScript("OnEnter")` in `pcall()`

2. **Quest abandon wrong quest** — hooks `QuestLogAbandonButton:OnClick()` to save title+index; hooks popup `OnAccept()` to restore selection by title before `AbandonQuest()` fires

3. **Quest reward tooltips** — hooks each `QuestInfoItem[1-6]:OnEnter()` to force `GameTooltip:SetOwner()` before `SetQuestItem()`, undoing pfQuest/Leatrix anchor theft

4. **Inspect tooltip cache expiry** — caches all 19 slot links on `INSPECT_READY`; `OnEnter()` hooks fall back to `SetHyperlink(cachedLink)` when live link is nil

**Pattern:** Separate frames for `PLAYER_LOGIN` and event handlers to avoid script clobbering.

---

### pfQuest-epoch

- Depends on `pfQuest-wotlk` (loaded after via `depend pfQuest-wotlk` in TOC)
- Removes unavailable Epoch content by setting entries to `{}`:
  ```lua
  pfDB["units"]["data-epoch"][15174] = {}  -- removes NPC
  pfDB["quests"]["data-epoch"][8369] = {}  -- removes quest
  ```
- Removals cover: Silithus NPCs, TBC quest NPCs, PvP quests not yet on server
- `patchtable.lua` patches quest objectives/rewards/level ranges for Epoch-specific changes

---

### pfQuest-wotlk

- Database: `pfDB["quests"]`, `pfDB["units"]`, `pfDB["objects"]`, `pfDB["items"]`
- Uses `hooksecurefunc('QuestLog_Update', ...)` (taint-safe, required for EpochFixes compatibility)
- **Minimap range-limited icons (Claude):** only draws icons within encounter range to reduce clutter

---

### unitscan

- LibCompat-1.0 backport embedded for 3.3.5 compatibility
- **QuickDispatch (Claude):** `pcall()`-based dispatch wraps scan callbacks to prevent crashes from bad data
- Scans nearby units via `UnitName()` + database lookup on `OnUpdate`

---

### ArkInventory

- Ace3 xpcall Lua 5.1 fix applied to event dispatchers:
  ```lua
  local ok, err = pcall(func, arg1, arg2)
  if not ok then handler(err) end
  ```
- Core files: `ArkInventory.lua`, `ArkInventoryStorage.lua`, `ArkInventoryRules.lua`, `ArkInventorySearch.lua`

---

### ItemRack / ItemRackOptions

- **NoBG flag (Claude):** `ItemRackUser[setName].NoBG = true`
- On `ZONE_CHANGED_NEW_AREA`: if in BG/Arena and current set has NoBG, auto-switch to default gear
- ItemRackOptions is LoadOnDemand — opens on first `/itemrack` command
- NoBG checkbox added to Sets panel in ItemRackOptions

---

### FavoriteContacts (ported from retail 12.0)

- Removed: `CreateFromMixins`, `EventRegistry`, `Settings` API, modern atlas icons
- Manual callback tables replace EventRegistry: `RegisterLoginCallback()`, `RegisterLoadUICallback()`
- `parentKey` pattern manually implemented
- MSA-DropDownMenu-1.0 (LibStub) for right-click context menus
- Contact format: `{recipient, icon, note}` stored in `FavoriteContactsSettings.contacts[index]`

---

### AuxTSMBridge

- Reads raw aux history strings directly (avoids aux temp-table allocator)
- Writes to TSM AuctionDB via `adbModule:DecodeItemData()` / `EncodeItemData()`
- Registers two TSM price sources: `AuxMarket`, `AuxMinBuyout`
- Rate-limited: syncs at most every 12 hours (`AuxTSMBridgeDB.lastSyncTime`)
- Guard: `d.quantity > 0` before encoding (nil quantity crashes TSM)
- Slash: `/axtsm sync` (force), `/axtsm status`

---

### TradeSkillMaster_AuctionDB

- Custom JSON parser (no LibJSON on 3.3.5)
- `decodeScans()` wrapped in `pcall()` — corrupt scan data no longer crashes
- Faction data merge: guards against nil faction tables
- Provides `DBMarket` and `DBMinBuyout` price sources to TSM formulas

---

### TradeSkillMaster_Crafting

- **Vellum support (Claude):** `Modules/VellumInfo.lua` maps enchantments → vellum item IDs; `CheapestVellum` logic picks cheapest available; DB migration converts existing recipes
- Scrap-conversion recipes excluded from intermediate crafting

---

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

**TOC load order:** `BuffWatcher_Data.lua` → `BuffWatcher.lua` → `BuffWatcher_Config.lua`

**Cross-file contracts:**
- `BW` table defined in Data.lua; extended in BuffWatcher.lua and Config.lua
- `BW.ROLES`, `BW.SPEC_ROLE_MAP`, `BW.DefaultRoleEntries`, `BW.ClassColors`, `BW.RoleColors` — all in Data.lua
- `BW.inspectResults[guid]` — cached `{ classFile, role }` per inspected player
- `BuffWatcherDB.roles[role].entries` — per-role buff entry arrays
- `BuffWatcherDB.specRoles` — optional override table

**SavedVariables:** `BuffWatcherDB` → `{ roles = { Tank = { entries = {...} }, ... }, specRoles = {}, buttonPos = {} }`

---

### DeleteItems

- Three named deletion lists (itemID-keyed, account-wide)
- Junk scanner: bags below `DIData.junkThreshold` copper, excluding `DIData.junkIgnore`
- No suffix/enchant differentiation — item ID only

---

### HCBreathBar

- Hides original breath bar (`SetAlpha(0)`), renders custom bar
- Sound alert below 20s: `PlaySoundFile("Sound\\Interface\\AlarmClockWarning1.wav")`
- Alert rate doubles below 10s
- Combat overlay warns against using spacebar to surface

---

### TitanSpeed

- Updates every 0.2s via `OnUpdate`
- Speed % = `GetUnitSpeed("player") / 7 * 100` (7 yards/sec = 100%)
- `SPEED_BUFF_INFO` table for buff name → bonus% mapping (English only)

---

### Magnify-Wotlk

- Zoom range: 1.0–4.0x (map), 1.0–10.0x (minimap), step 0.2 / 0.1
- `MagnifyOptions.enablePersistZoom`: remembers pan/zoom per zone
- Resizes quest POI buttons to match zoom via `ResizeQuestPOIs()`
- Mapster compatibility: disables Mapster POI handler if present

---

## SavedVariables Quick Reference

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

---

## Other Projects

- **warcraftlogs-epoch:** `C:\Dev\warcraftlogs-epoch` — use this path for all file edits and git operations for that project
