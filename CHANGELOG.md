# Addon Changelog — Ascension (WoW 3.3.5a / Interface 30300)

All addons modified or created with Claude Code assistance for the Ascension private server.

---

## NEW ADDONS (Created from scratch)

### DeleteItems
- **Purpose:** Item deletion utility with three independent deletion lists and a junk scanner
- Scans bags for gray/white items below a configurable sell-price threshold
- Suggests items for deletion with price display (gold/silver/copper) and ignore list support
- Object pooling for efficient UI row rendering
- Account-wide SavedVariables with migration support for old save formats

### TitanSpeed
- **Purpose:** Titan Panel plugin that displays the player's current movement speed as a percentage
- Detects active speed buffs (Druid forms, Sprint, Ghost Wolf, mounts, speed potions)
- Shows yards/sec and active speed sources in tooltip
- Polls every 0.2 seconds via `OnUpdate`

### EpochFixes
- **Purpose:** Patches four distinct client bugs specific to the Ascension/Epoch environment
- **Fix 1 — SpellBook tab:** Wraps `OnEnter` handler in `pcall()` to suppress nil concatenation error when `TOGGLEPETBOOK` keybind is unassigned
- **Fix 2 — Quest abandon:** Captures quest log index before abandon popup opens; re-selects correct quest when popup is accepted, preventing index shift from other addons (e.g. Leatrix)
- **Fix 3 — Quest reward tooltips:** Hooks quest item `OnEnter` events to reclaim `GameTooltip` ownership when pfQuest or Leatrix corrupt the tooltip anchor state
- **Fix 4 — Inspect tooltips:** Caches all 19 equipped item links on `INSPECT_READY`; falls back to cached links after API returns nil (~10–15 seconds after cache expiry)

### AuxTSMBridge
- **Purpose:** Two-way price data bridge between Aux auction scanner and TradeSkillMaster
- Registers two TSM price sources: `AuxMarket` (weighted median) and `AuxMinBuyout` (daily low)
- Auto-syncs all Aux scanned prices into TSM AuctionDB when the Auction House closes (throttled to once per 12 hours)
- Calculates weighted median with exponential time decay (0.99^days_ago)
- Parses Aux's raw history strings directly to avoid crash when calling Aux's Lua functions thousands of times synchronously
- Slash commands: `/axtsm sync` (manual sync), `/axtsm status`

---

## PORTED ADDONS (Modified for 3.3.5a compatibility)

### ItemRack (v2.243)
**New Feature — "Disable in BG/Arena" per-set option:**
- Added `NoBG` flag to the set data structure (`ItemRackUser.Sets[name].NoBG`)
- `ItemRackEvents.lua`: Checks `inPVP` + `NoBG` flag before equipping in all three event processors — stance events (line 324), zone events (line 360), and buff events (line 397)
- Prevents any automatic set equip trigger while player is inside a battleground or arena

### ItemRackOptions (v2.243)
**New Feature — "Disable in BG/Arena" checkbox in Sets panel:**
- Added `"Disable in BG/Arena"` label string to `ItemRack.CheckButtonLabels`
- Added `ItemRackOptSetsNoBGCheckButton` (20×20, `ItemRackOptSimpleCheckButton` template) anchored below the Hide checkbox in `ItemRackOptSubFrame2`
- `ItemRackOpt.NoBGSet()` function reads checkbox state and writes/clears `NoBG` on the active set
- Checkbox is disabled when no set is selected; enabled and synced to saved value when a set is loaded
- Increased Sets panel frame height to accommodate new checkbox

### FavoriteContacts (v2.13.1) — Ported from Retail 12.0
**API compatibility fixes:**
- Replaced `C_AddOns.GetAddOnMetadata` → `GetAddOnMetadata`
- Replaced `Settings.RegisterAddOnCategory` → `InterfaceOptions_AddCategory`
- Replaced `Settings.RegisterCanvasLayoutCategory` → standard options frame registration
- Added double-call of `InterfaceOptionsFrame_OpenToCategory()` to work around 3.3.5 panel focus bug
- Guarded `slider:SetObeyStepOnDrag()` — not available in 3.3.5

**UI framework compatibility:**
- Replaced `parentKey` attribute (not supported in 3.3.5) throughout all XML with `name="$parentXxx"` naming convention; all child access updated to use `_G["ParentNameXxx"]` pattern
- Replaced `SetSize(w,h)` → separate `SetWidth()` / `SetHeight()` calls
- Replaced radio button and slider child access with `_G[name.."Text/Low/High"]` pattern
- Manually created `OkayButton` and `CancelButton` via `UIPanelButtonTemplate` (retail's `SelectionFrameTemplate` not available)
- Backdrop uses standard tooltip textures (`UI-Tooltip-Background`, `UI-Tooltip-Border`)
- Replaced retail icon references with a curated 64-icon palette confirmed available in the 3.3.5 client
- Added type guards on saved position coordinates (`type(posX) == "number"`)

### TradeSkillMaster_Crafting (v2.5.2)
**New Feature — Vellum support for enchanting crafts:**
- Added `VellumInfo.lua`: lookup table mapping enchanting spell IDs to the correct vellum item IDs (38682, 37602, 39349, 39350, 43145, 43146)
- Added `CheapestVellum()` function: automatically substitutes a lower-tier vellum with Vellum III when it's cheaper; guards against `nil` returns from `GetItemInfo()`
- Vellum cost integrated into crafting cost display and tooltip breakdown
- `OnEnable()` migration routine: fixes legacy vellum item string formatting in saved DB (converts bare item IDs to full `item:id:0:0:0:0:0:0` format)

### TradeSkillMaster_AuctionDB (v2.3.10)
**Bug fixes — data encoding guards:**
- Added nil and empty-string guards in `decodeScans()` to prevent corruption when day or market value data fails to decode
- Double-validates decoded `day` value before creating scan entries

**Custom data parsing:**
- Added `DecodeJSON()` function using `gsub()` + `loadstring()` to parse JSON-like app data into Lua tables
- Supports realm/faction data merging with multi-hyphen realm name parsing
- Accepts cross-faction auction data imports within a configurable `MAX_AVG_DAY` time window

### ArkInventory
**Ace3 library xpcall fix (Lua 5.1 / 3.3.5 compatibility):**
- All embedded Ace3 libraries (AceGUI-3.0, AceAddon-3.0, AceTimer-3.0, AceConfigDialog-3.0, AceBucket-3.0, CallbackHandler-1.0) use the `CreateDispatcher(argCount)` pattern — generates closures via `loadstring` that capture arguments before calling `xpcall(call, errorhandler)` with no extra args, working around the 3.3.5 limitation where `xpcall(f, h, ...)` silently drops variadic arguments

### Magnify-Wotlk
- Settings panel uses `InterfaceOptions_AddCategory` / `InterfaceOptionsFrame_OpenToCategory` (3.3.5 API)
- `WORLD_MAP_UPDATE` event timing fix: wraps `SetMapToCurrentZone()` to suppress BattlefieldMinimap's automatic zone reset, accounting for 3.3.5's OnUpdate-before-event dispatch order
- All hooking done via `hooksecurefunc()` — no CreateFromMixins or EventRegistry
- Textures use `CreateTexture()` + `SetTexture()` — no `SetAtlas` or `SetColorTexture`

### HCBreathBar
- Hooks `OnUpdate` for all MirrorTimer frames; detects BREATH type and replaces the default bar with a custom `StatusBar`
- Sound uses `PlaySound("igQuestComplete")` — valid 3.3.5 sound name (not modern SoundKit IDs)
- Uses `SetStatusBarTexture()` and `SetStatusBarColor()` — standard 3.3.5 API

### FeralAPFix
- Wraps `GameTooltip:SetHyperlink()` with a nil guard — prevents crash when Ascension's built-in `feral-attack.lua` calls `GetItemInfo(link)` with a nil link triggered by TSM's LibExtraTip tooltip callbacks

### unitscan
- Uses `GetBuildInfo()` build detection (`isWOTLK = build == 30300`) for version-specific UI code
- `LibCompat-1.0` backport library included: provides `IsInRaid()`, `IsInGroup()`, `GetNumGroupMembers()`, `UnitIterator()`, `GetUnitIdFromGUID()` for 3.3.5
- `LibCompat-1.0` uses `pcall` (not `xpcall`) in `QuickDispatch()` — correct for Lua 5.1
- Class color system checks for `CUSTOM_CLASS_COLORS`, falls back to `RAID_CLASS_COLORS`; manually adds missing `colorStr` fields including Death Knight

### pfQuest-epoch
- Epoch-specific NPC/quest database layered over pfQuest-wotlk via `patchtable()` merge system
- `overwrites.lua` removes content not present on Epoch (Silithus NPCs, TBC quest givers, Zul'Aman island)
- Version checking via `GetAddOnMetadata()` with addon messaging for update notifications

### pfQuest-wotlk
- Multi-client compatibility layer (`compat/client.lua`): detects build version and maps API differences between Vanilla/TBC/WotLK
- `string.gmatch or string.gfind` fallback for Lua 5.0 vs 5.1
- `mod or math.mod` fallback for math function rename
- Quest frame name mappings for 3.3 renames (`QuestLogQuestTitle` → `QuestInfoTitleHeader`, etc.)
- `QuestWatchFrame` vs `WatchFrame` handled per client version
- Item link suffix format differs per client (`":0:0:0"` vs `":0:0:0:0:0:0:0:0"`)
- Wowhead database URL selected per client (wotlk/tbc/classic)

### TitanGoldTracker
- Uses `UIDropDownMenu_AddButton()` for context menus (not modern `MenuUtil`)
- Uses Ace3 timer wrappers (`ScheduleRepeatingTimer`, `CancelTimer`) — no `C_Timer` dependency
- Uses `hooksecurefunc()` for safe function hooking
- All frame templates are standard 3.3.5 Titan Panel templates
