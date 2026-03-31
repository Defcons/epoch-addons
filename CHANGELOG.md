# Addon Changelog — Ascension (WoW 3.3.5a / Interface 30300)

All addons modified or created with Claude Code assistance for the Ascension private server.

---

## TitanPerformance v1.0 — Memory Monitor Integration *(2026-03-31)*
- **Memory monitor frame:** Left-clicking the Performance button now opens a full addon memory monitor instead of running garbage collection
- **Per-addon breakdown:** Scrollable, sortable list of all loaded addons showing current memory usage and growth since login
- **Leak detection:** Color-coded growth tracking (green < 2MB, yellow < 5MB, orange < 10MB, red > 10MB) with percentage growth in tooltips
- **Force GC button:** Garbage collection moved to a button inside the monitor frame
- **Reset Baseline button:** Restart growth tracking from current values at any time
- **Sortable columns:** Click column headers (Addon Name, Memory, Growth) to sort ascending/descending
- **Auto-refresh:** Updates every 5 seconds while the monitor frame is open

## EpochFixes v1.1 — Quest Log Selection Drift Fix *(2026-03-31)*
- **Root cause found:** `pfQuest-epoch/pfQuest-nameplates.lua` `ScanQuestObjectives()` called `SelectQuestLogEntry()` on every quest in a loop without saving/restoring the selection, shifting the selected quest while the quest log was open
- **Three-layer fix in EpochFixes:**
  - (A) Guard `SelectQuestLogEntry`: blocks addon-driven calls (from Leatrix, pfQuest-epoch) when `QuestLogFrame` is visible
  - (B) Re-call `SetAbandonQuest()` in popup `OnAccept` to fix C++ internal state — `AbandonQuest()` reads from `SetAbandonQuest()`, not `GetQuestLogSelection()`
  - (C) Block ALL `SelectQuestLogEntry` calls while the abandon confirmation popup is open
- Added `OnHide` handler for popup dismissed via Escape key

## pfQuest-epoch v1.1 — Nameplate Scanner + Commission Quests + Chest Cleanup *(2026-03-31)*
- **Nameplate scanner fix:** `ScanQuestObjectives()` now saves/restores quest log selection around its iteration loop, preventing quest log drift
- **Commission quest visibility:** "Commission for..." quests now bypass the low-level quest filter on zone maps, minimap, and world map
- **Chest list cleanup:** Removed non-treasure entries from chest tracking (PvP supply crates, quest objects like Cat Figurine/Defias Gunpowder, Giant Clams, etc.)
- **Continent debug mode:** Added `epochDebugContinent` config option for debugging world map node rendering

## Aux-addon v1.1 — Auction Tooltip Fix *(2026-03-31)*
- **Tooltip hook fix:** Auction listing tooltips now use `SetHyperlink` instead of `load_tooltip`/`extend_tooltip`, so TSM and LibExtraTip price hooks fire correctly

## TitanGoldTracker v1.1 — BoP Item Detection *(2026-03-31)*
- **BoP/quest item detection:** New `GT_IsTradeable()` function checks items via hidden scan tooltip for "Binds when picked up" and quest item type
- **Accurate wealth tracking:** Untradeable items (BoP, quest items) now use vendor sell price instead of AH price for bag/bank value calculations
- New session caches: `GT_TradeableCache`, `GT_ScanTooltip`

---

## ArkInventory — Fix Bag Open/Drag Freeze *(2026-03-31)*
- **Removed redundant bulk category wipe** in `Frame_Main_Draw` that cleared `i.cat` on ALL items whenever any bag data changed
- `ScanBag` already clears `i.cat` per-item for changed items (line 1344); the bulk wipe in the draw path forced expensive tooltip scanning + PeriodicTable lookups for the entire inventory (~150-200 items) even when only 1 item changed
- This caused multi-second freezes on first bag open after login and on subsequent bag updates (BAG_UPDATE events from mail, AH, quest items, etc.)
- Full category wipe still occurs on rule/profile changes via `ItemCacheClear()` where it's actually needed

---

## BuffWatcher v1.0 — Per-Role Redesign *(2026-03-31)*
- **Complete rewrite:** BuffWatcher2 renamed to BuffWatcher; old BuffWatcher and BuffWatcher2 both deleted
- **Per-role buff configs:** 4 roles (Tank, Healer, Melee, Ranged) each with independent buff/consume entry lists
- **Talent-based spec detection:** Player's spec detected from talent tab point distribution; raid members inspected via `NotifyInspect()` queue (one at a time, 3s timeout, class-default fallback)
- **Spec → Role mapping:** Hardcoded defaults for all vanilla classes with TBC talents; user can override any spec's role in the Config panel (e.g. change Feral Druid from Melee to Tank)
- **Config UI:** UIDropDownMenu role selector at top; editing entries applies to the selected role only; "Spec Overrides" button opens side panel with click-to-cycle role buttons per class/spec
- **Status frame:** New Role column showing each player's detected role (colour-coded)
- **Export:** TSV now includes Role column; labels not applicable to a player's role show "-" instead of OK/MISSING
- **Migration:** Automatically imports old `BuffWatcher2DB` entries into all roles if present
- **Slash commands:** `/bw`, `/bw config`, `/bw check`, `/bw export`, `/bw inspect`, `/bw help`
- **Group events:** Re-inspects on `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE`

---

## Repo Cleanup *(2026-03-31)*
- **EpochFixes:** Known issues may be server-side rather than client-side; needs further investigation

---

## ArkInventory — Auto-Sell by Category *(2026-03-31)*
- **Auto-sell at vendor:** Items in categories flagged as "autosell" are automatically sold when opening a merchant window. Works with any item quality (grey, white, green, etc.)
- Per-category `autosell` flag stored in global SavedVariables (persists across characters)
- Checkbox added to custom category config panel (ArkInventory settings → Categories → Custom → [category] → "Auto-Sell at Vendor")
- Slash commands: `/arkinv autosell <name>` toggles auto-sell for a category, `/arkinv autosell list` shows enabled categories
- Chat summary printed after selling (e.g., "Auto-sold 5 item(s) for 1g 23s 45c")
- Files modified: `ArkInventory.lua` (DB defaults + AutoSellCategories function), `ArkInventoryStorage.lua` (MERCHANT_SHOW hook), `ArkInventoryConfig.lua` (UI checkbox + slash commands)

---

## TradeSkillMaster_Crafting *(2026-03-29)*
- **Leather intermediate-craft block:** Leatherworking queue no longer auto-crafts leather types (Light/Medium/Heavy/Thick/Rugged/Knothide/Borean Leather) as intermediate steps — they are treated as raw materials to buy/gather instead. Fixes Ruined Leather Scraps scrap-conversion recipe being incorrectly queued (`Queue.lua`: `LEATHER_BLOCKLIST`, `IsLeatherItem`, guard in `FindIntermediateSpellID`)

---

## NEW ADDONS (Created from scratch)

### BuffWatcher2 *(2026-03-29)*
- **Purpose:** Complete rewrite of BuffWatcher — configurable raid buff/consumable checker with Excel export
- Flat entry list: each entry maps a WoW buff name to an output label; entries sharing a label are grouped (any one match = requirement met)
- Two-column editable config frame: Buff Name | Output Label, with enable/disable checkbox and delete button per row
- TBC-focused defaults: Battle Elixir (7 elixirs), Guardian Elixir (4), Flask (4), Well Fed, plus world buffs
- **Export frame** (`/bw2 export`): produces tab-separated values (TSV) with one column per requirement label, pasteable into Excel via Ctrl+A, Ctrl+C
- Export includes ALL group members (OK/MISSING per label), sorted by most-missing-first
- Multi-line EditBox with "read-only" guard (OnTextChanged reverts edits) and Select All button
- Status frame: Player | Missing Buffs quick-glance view (only shows players missing something)
- Reset to Defaults button with StaticPopup confirmation dialog
- Draggable button with saved position, hover-to-open status, 5s auto-refresh
- Slash: `/bw2`, `/bw2 config`, `/bw2 check`, `/bw2 export`, `/bw2 help`
- Plain EditBox + backdrop Frame wrappers (avoids InputBoxTemplate auto-focus bugs from v1/v2)
- All state on `BW2` table, SavedVariables: `BuffWatcher2DB`

### BuffWatcher *(2026-03-27, updated 2026-03-27)*
- **Purpose:** Raid buff and consumable checker — converted from a WeakAura to a standalone addon
- Small draggable "BuffWatcher" button; hover (or left-click) opens the status popup
- Status popup auto-refreshes every 5 s while visible; mousewheel scrolls long results
- Categorises players into **MVPs** (flask + all buffs), **Greedy** (only missing flask), and **Missing** (detail view of every absent buff/consume)
- Per-class config in `BuffWatcher_Config.lua`: separate `worldbuffs` and `consumes` lists; any listed buff name counts as "present"
- Zandalar toggle: `/bw zan` or in-frame button excludes `zandalar = true` entries from checks
- Right-drag button to reposition; position persisted in `BuffWatcherDB`
- Slash: `/bw` toggle · `/bw check` force scan · `/bw zan` toggle Zandalar · `/bw help`
- Supports all vanilla classes: Warrior, Paladin, Hunter, Rogue, Priest, Mage, Warlock, Druid, Shaman
- Uses native 3.3.5 API: `UnitBuff()` index loop, `GetNumRaidMembers()`, `GetNumPartyMembers()`; no C_Timer
- **Fix (2026-03-27):** Moved all cross-file globals (`BW_Data`, `BW_ClassColors`, `BW_IsEnabled`) into the `BW` table (`BW.Data`, `BW.ClassColors`, `BW.IsEnabled`) to prevent clobbering by other addons sharing the global namespace — this was causing `BW_Data is nil` on every config-frame tab click

---

### QuestRewardIcons *(2026-03-27)*
- **Purpose:** Overlays small icons on quest choice reward items showing which has the best vendor or disenchant value
- Gold-coin icon on the item with the highest vendor sell price
- Enchanting icon on the item with the highest expected DE value
- Winner icon is larger (18px) with a coloured background (yellow=gold, blue=DE); loser is smaller (13px) and dimmed
- Gold wins if its value is ≥ DE value + 30s (configurable `GOLD_THRESHOLD`)
- DE values use a static lookup table by quality + item level bracket (Strange Dust through Abyss Crystal era); values tunable to server economy
- When best vendor and best DE item are the same button, both icons stack side by side
- Only activates when quest has ≥ 2 choice items; hooks `QuestInfo_Display` + `QUEST_COMPLETE`/`QUEST_GREETING` events

---

### DeleteItems
- **Purpose:** Complete ground-up rewrite of a basic item-deletion addon; full feature list below

**Core data layer**
- Three independent deletion lists (`list1`/`list2`/`list3`) stored in `DIData` (`SavedVariables` — account-wide, shared across all characters)
- Data migration path: old `DITotalSavedItems` / `DICurrentList` format automatically converted on first load
- String keys for all item IDs (prevents WoW SavedVariables numeric-key serialisation quirks)
- `activeList` persisted across sessions

**Main window**
- Scrollable item list with alternating row backgrounds, rarity colour-coding, and per-item vendor price shown inline
- Drag-and-drop zone: drag any item from bags directly onto the zone to add it to the active list
- Per-row `[Remove]` button; row tooltip shows the full item tooltip
- Three list-tab buttons at the top — **left-click** switches list, **right-click** opens a rename dialog (`StaticPopup` with `hasEditBox`)
- Per-list **notes** field (auto-saves on focus lost, Escape to revert, placeholder text)
- `[Delete Items From Bags]` button — requires **Shift+click** to confirm; tooltip shows live count of matching bag slots and total vendor value that would be destroyed
- `[Clear List]` button with confirmation popup
- `[Scan Bags for Junk Suggestions]` button to open the junk scanner

**Launcher button**
- Small draggable frame button always visible on screen (replaces minimap button)
- **Hover tooltip:** shows active list name, number of matching bag slots that would be freed, and total vendor value to be destroyed
- **Click:** toggle the main window open/close
- **Shift+click:** delete immediately without opening the window
- Drag to reposition anywhere on screen

**Junk scanner**
- Separate draggable frame (430 px wide) anchored to the right of the main window
- **Threshold control:** `Max sell price (gray/white):` edit box (silver) — `0` shows all grays regardless of price; `> 0` shows gray and white items whose sell price per item is ≤ the threshold
- `[Scan Bags Now]` button — reads current threshold, scans all bags, results sorted cheapest first
- Per-row layout: item icon + name (quality colour) on line 1; formatted vendor price/ea + bag count + max-stack hint on line 2; stacked `[Add to List]` and `[Ignore]` buttons on the right
- `[Add All Suggestions to Active List]` — bulk-adds all current results
- Per-item **Ignore** button: adds item to `DIData.junkIgnore`; ignored items never appear in future scans
- `[Clear Ignored Items (N)]` button — shows live count, disabled when list is empty
- Items already in any deletion list are automatically excluded from scan results
- Object pooling (`junkRowPool`) for efficient re-renders

**Slash commands**
- `/di` — open/close window
- `/di add <id|link>`, `/di rem <id>`, `/di del`, `/di list`, `/di clear`
- `/di set list1|list2|list3`, `/di junk` — open junk scanner

### TitanSpeed
- **Purpose:** Titan Panel plugin that displays the player's current movement speed as a percentage
- Detects active speed buffs (Druid forms, Sprint, Ghost Wolf, mounts, speed potions)
- Shows yards/sec and active speed sources in tooltip
- Polls every 0.2 seconds via `OnUpdate`
- **Speed buff display:** tooltip now shows each active speed buff with its bonus percentage, e.g. `Cat Form (+30%)`, `Sprint (+70%) - 9s`; rank-varying spells (Sprint, Dash) resolve the correct % from the rank string returned by `UnitBuff`; timed buffs show remaining seconds

### EpochFixes
- **Purpose:** Patches four distinct client bugs specific to the Ascension/Epoch environment
- **Fix 1 — SpellBook tab:** Wraps `OnEnter` handler in `pcall()` to suppress nil concatenation error when `TOGGLEPETBOOK` keybind is unassigned
- **Fix 2 — Quest abandon:** Hooks `QuestLogAbandonButton:OnClick` to snapshot the quest log selection index; wraps `StaticPopupDialogs["ABANDON_QUEST"].OnAccept` to call `SelectQuestLogEntry(savedIndex)` just before `AbandonQuest()` runs — guarantees the right quest is selected at the last possible moment regardless of what other addons (e.g. Leatrix auto-quest scan via `SelectQuestLogEntry` loop) did to the selection while the popup was open; works in tandem with pfQuest-wotlk/quest.lua raw-override fixes
- **Fix 3 — Quest reward tooltips:** Hooks quest item `OnEnter` events to reclaim `GameTooltip` ownership when pfQuest or Leatrix corrupt the tooltip anchor state
- **Fix 4 — Inspect tooltips:** Caches all 19 equipped item links on `INSPECT_READY`; falls back to cached links after API returns nil (~10–15 seconds after cache expiry)

### AuxTSMBridge
- **Purpose:** Two-way price data bridge between Aux auction scanner and TradeSkillMaster
- Registers two TSM price sources: `AuxMarket` (weighted median) and `AuxMinBuyout` (daily low)
- Auto-syncs all Aux scanned prices into TSM AuctionDB when the Auction House closes (throttled to once per 12 real hours, persisted across sessions via `AuxTSMBridgeDB` SavedVariable)
- Calculates weighted median with exponential time decay (0.99^days_ago), replicating Aux's own algorithm
- Parses Aux's raw history strings directly instead of calling `auxHistory.value()` in a loop — the latter goes through Aux's temp-table allocator (`T.lua`) and causes `memory allocation error: block too big` when called thousands of times synchronously outside Aux's execution context
- Slash commands: `/axtsm sync` (force immediate sync, resets the 12-hour timer), `/axtsm status`

**Bug fixes:**
- `quantity = 0` written during sync encoded to TSM's sentinel `"~"` which decodes back to `nil`; TSM's tooltip then calls `format("%d auctions", nil)` and crashes — fixed by defaulting to `1` in the bridge and adding `or 0` guard directly in `TradeSkillMaster_AuctionDB.lua` line 295
- `AUCTION_HOUSE_CLOSED` fires twice in 3.3.5 (Aux hides its frame in the same event, re-triggering it); the 12-hour cooldown naturally absorbs the double-fire
- Removed noisy login message "Registered AuxMarket and AuxMinBuyout as TSM price sources"

---

## PORTED ADDONS (Modified for 3.3.5a compatibility)

### NotPlater-3.3.5
**Bug fix — "Usage: UnitDetailedThreatSituation" error (`modules/threat-3.3.5.lua`):**
- `GetThreat` and `GetMaxThreatOnTarget` called `UnitDetailedThreatSituation` unconditionally; compound unit tokens like `"pet-target"` and stale/non-existent units cause the API to throw a hard Lua error in combat
- Fixed by adding `UnitExists()` guards in both functions before calling the API; invalid units return `nil`/`0` safely instead

**Bug fix — login crash "table index is nil" (`modules/threat-3.3.5.lua:80`):**
- `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE` are called from `OnInitialize` before `PLAYER_LOGIN`, at which point `UnitGUID("player")` returns nil — using nil as a table key is a hard Lua error
- Fixed by storing all `UnitGUID()` calls in locals and nil-checking before assigning: `playerGuid`, `UnitGUID("party"..i)`, and `UnitGUID("raid"..i)` all guarded

**Bug fix — "High Threat" color never displayed (`modules/threat-3.3.5.lua`):**
- `lastThreat` was keyed by volatile unit-ID strings (`"mouseover"`, `"party1-target"`, etc.) which change between calls, so the threat-trajectory comparison (`highestThreat - (playerThreat + 3*(playerThreat - lastThreat[unit]))`) always saw `nil` and skipped the High Threat (c2) state entirely
- Fixed by adding `healthFrame.lastUnitGuid` (stable GUID) stored alongside `lastUnitMatch` at all three match sites (`group target`, `mouseover`, `focus`) in `ThreatCheck`, in `MouseoverThreatCheck`, and cleared in `ThreatComponentsOnShow`
- `lastThreat` now keyed and read by GUID instead of unit-ID string

**Bug fix — `MouseoverThreatCheck` ignored its `guid` parameter:**
- Was always setting `lastUnitMatch = "mouseover"` and discarding the passed-in `guid`; now also sets `lastUnitGuid = guid` so the stable key is available for `lastThreat`

**Bug fix — `tgetn(group)` on a hash table always returned 0:**
- `group` is keyed by GUID (hash table), so `table.getn` always returned 0, making the number-text ranking threshold division wrong
- Replaced with `groupSize` counter incremented inside the existing loop, with a `groupSize > 1` guard

**Bug fix — `ThreatComponentsOnShow` crash on login ("Font not set"):**
- `SetText("")` was called on FontStrings before `ConfigureThreatComponents` had set their font, causing a Lua error on every nameplate shown at login
- Fixed by guarding with `if healthFrame.threatDifferentialText:GetFont() then`

**Feature — solo play support (Hunter pet threat):**
- `PARTY_MEMBERS_CHANGED` now always builds `self.party` (previously `nil` when solo), always including `"player"` and `"pet"` if present
- `ThreatCheck` and `MouseoverThreatCheck` gate changed from `UnitInParty/UnitInRaid` check to `if group then`, so solo always runs the full threat path
- Solo correction in `OnNameplateMatch`: `UnitDetailedThreatSituation` for the pet may return `nil` when not in a party/raid, causing `highestThreat == playerThreat` and always showing c1; fixed by reading the player's own `status` field (0/1 = not tanking, 2/3 = tanking) and bumping `highestThreat` when the API confirms the player is not the aggro holder

### ItemRack (v2.243)
**New Feature — "Disable in BG/Arena" per-set option:**
- Added `NoBG` flag to the set data structure (`ItemRackUser.Sets[name].NoBG`)
- `ItemRackEvents.lua`: Checks `inPVP` + `NoBG` flag before equipping in all three event processors — stance events (line 324), zone events (line 360), and buff events (line 397)
- Prevents any automatic set equip trigger while player is inside a battleground or arena

**Bug fix — trinket autoqueue cross-slot stop:**
- `ItemRackQueue.lua` `ProcessAutoQueue()`: added paired-slot buff check using `SlotInfo[slot].other`
- When either trinket fires and its buff becomes active, the *other* trinket's queue now also pauses — preventing unnecessary swaps during the 20-second shared trinket cooldown
- Fix is symmetric: works regardless of which trinket (slot 13 or 14) was used first

### ItemRackOptions (v2.243)
**New Feature — "Disable in BG/Arena" checkbox in Sets panel:**
- Added `"Disable in BG/Arena"` label string to `ItemRack.CheckButtonLabels`
- Added `ItemRackOptSetsNoBGCheckButton` (20×20, `ItemRackOptSimpleCheckButton` template) anchored below the Hide checkbox in `ItemRackOptSubFrame2`
- `ItemRackOpt.NoBGSet()` function reads checkbox state and writes/clears `NoBG` on the active set
- Checkbox is disabled when no set is selected; enabled and synced to saved value when a set is loaded
- Increased Sets panel frame height to accommodate new checkbox

**Bug fix — "stop queue here" always available for all slots:**
- `PopulateSortList()`: unconditionally calls `AddToSortList(sortList, 0)` after the item loop
- Previously the `0` sentinel ("-- stop queue here --") was only added when `AllowEmpty=="ON"` AND the slot had an item equipped AND the bank was closed — meaning slot 14 (bottom trinket) would often be missing the stop marker
- Since `AddToSortList` deduplicates, this is safe to call unconditionally and decouples queue-control from the empty-slot-in-menu setting

### FavoriteContacts (v2.13.1) — Ported from Retail 12.0
**API compatibility fixes:**
- Replaced `C_AddOns.GetAddOnMetadata` → `GetAddOnMetadata`
- Replaced `Settings.RegisterAddOnCategory` → `InterfaceOptions_AddCategory`
- Replaced `Settings.RegisterCanvasLayoutCategory` → standard options frame registration
- Added double-call of `InterfaceOptionsFrame_OpenToCategory()` to work around 3.3.5 panel focus bug
- Guarded `slider:SetObeyStepOnDrag()` — not available in 3.3.5

**UI framework compatibility (XML / Lua):**
- Replaced `parentKey` attribute (retail-only) throughout all XML with `name="$parentXxx"` naming; all child access updated to `_G["ParentNameXxx"]` pattern
- Replaced `relativeKey` anchor references with explicit `relativeTo="globalName"` in all `<Anchor>` elements
- Removed `inherits="SelectionFrameTemplate"` (retail-only); `OkayButton` and `CancelButton` created programmatically via `UIPanelButtonTemplate` instead
- `UIRadioButtonTemplate` child FontString: `parentKey` is ignored in 3.3.5; buttons explicitly named `FavoriteContactsRadioButton1…N` and `.text` assigned via `_G[name.."Text"]`
- Replaced `SetSize(w,h)` → separate `SetWidth()` / `SetHeight()` calls throughout
- Removed 5th `CreateFrame` argument (not supported in 3.3.5)
- `FauxScrollFrame_GetOffset()` returns nil before first scroll in 3.3.5 — added `or 0` at both call sites
- Removed the `ListScrollFrameTemplate` ScrollFrame from the icon picker entirely — 56 icons fit in 8×7 slots without scrolling, making `FauxScrollFrame_Update` and its `_G[name.."ScrollBar"]` lookup unnecessary; `scrollOffset` hardcoded to `0`

**Contact button container (`ContactContainer.lua`):**
- Added dark `SetBackdrop` (tooltip textures) with `SetBackdropColor(0,0,0,0.85)`; grey border when locked, gold border when unlocked
- `SetMovable(true)` + drag support: container moves freely when unlocked; position saved to `settings.posX`/`settings.posY` via `GetLeft()`/`GetTop()` on `DragStop`
- Right-click toggles `settings.locked`; border colour updates immediately
- Removed all `OpenMailFrame:ClearAllPoints()`/`SetPoint()` calls — repositioning mail child frames externally breaks 3.3.5 mail UI layout

**Settings (`Settings.lua`):**
- Default `scale` changed from `"AUTO"` to `0.75` (AUTO scaled buttons to fill MailFrame height, making them oversized)
- Added `locked = true`, `posX = false`, `posY = false` to `defaultSettings` and `ResetUISettings`

**Icon palette (`EditPopup.lua`):**
- Replaced all `ClassIcon_*` (not in this client's MPQ) and `ability_*`/`spell_*` class icons (unreliable in this client) with `inv_*` item icons present in vanilla WoW 3.3.5
- Vanilla classes only (no Death Knight): Warrior `inv_sword_04`, Paladin `inv_hammer_01`, Hunter `inv_weapon_bow_07`, Rogue `inv_weapon_shortblade_05`, Priest `inv_staff_01`, Shaman `inv_jewelry_talisman_04`, Mage `inv_wand_07`, Warlock `inv_staff_09`, Druid `inv_misc_monsterclaw_04`
- Race icons use `achievement_character_*` (WotLK achievement icons, confirmed working in this client): 10 Alliance + 8 Horde races
- Profession icons: `Trade_*` and `inv_*` prefixes (confirmed working) — Alchemy, Blacksmithing, Enchanting, Engineering, Herbalism, Inscription, Jewelcrafting, Leatherworking, Mining, Skinning, Tailoring, Fishing, Cooking, First Aid
- Miscellaneous icons: bags, bank/vault, key, note, PvP banners (`INV_BannerPVP_01/02`)
- Added type guards on saved position coordinates (`type(posX) == "number"`)

### TradeSkillMaster_Crafting (v2.5.2)
**New Feature — Vellum support for enchanting crafts:**
- Added `VellumInfo.lua`: lookup table mapping enchanting spell IDs to the correct vellum item IDs (38682, 37602, 39349, 39350, 43145, 43146)
- Added `CheapestVellum()` function: automatically substitutes a lower-tier vellum with Vellum III when it's cheaper; guards against `nil` returns from `GetItemInfo()`
- Vellum cost integrated into crafting cost display and tooltip breakdown
- `OnEnable()` migration routine: fixes legacy vellum item string formatting in saved DB (converts bare item IDs to full `item:id:0:0:0:0:0:0` format)

**Crafting queue — intermediate craft flattening overhaul (`Queue.lua`):**
- Added `FindIntermediateSpellID(itemString)` helper: finds the best spell for crafting an item as an intermediate; tries cost-based `GetLowestCraftPrices` first, falls back to direct `craftReverseLookup` scan when pricing data is absent (e.g. items with no AH data on the private server); prefers non-cooldown crafts
- `GetIntermediateCrafts`: replaced the old `craftCost and lowestCost and craftCost <= lowestCost` gate — intermediates are now always expanded whenever a known craft exists, not only when TSM pricing data is available; uses `FindIntermediateSpellID`
- `HasLoop`: updated to use `FindIntermediateSpellID` so loop detection mirrors the new expansion logic
- Bug fix: `usedMats` re-add at end of `GetQueue()` now skips zero-quantity entries; previously an intermediate craft with zero inventory would be re-inserted into the materials table with `quantity = 0`, causing it to appear in the materials list as "Need 0 / Total 0"
- Materials calculation reverted to always use full `data.queued` (removed an earlier `effectiveQueued` reduction that caused materials to show Total = 0 when result items were stocked on any character)
- Added `HasPoorQualityMat(spellID)` guard: skips any intermediate craft whose mats include a gray (quality 0) item — prevents scrap-conversion recipes (e.g. 5x Ruined Leather Scraps → Light Leather) from being used as intermediates; regular leather types are shown as-is in the materials list instead

**Crafting queue — alt-stock awareness (`CraftingGUI.lua`):**
- Queue display now shows `(X stocked, craft Y)` annotation next to each craft name when `GetTotalQuantity` detects you already have some of the result item across all characters; correctly reduces the "effective crafts needed" count in the annotation without affecting the materials list
- Bug fix (`UpdateQueue`): `TSM.db.factionrealm.tradeSkills[UnitName("player")]` nil-guarded with `or {}`; previously crashed when a character that had never scanned professions with TSM opened the queue panel (e.g. a bank alt opening First Aid)

**New slash command — `/tsm queue` (`TradeSkillMaster_Crafting.lua`):**
- Added `/tsm queue` slash command that opens/closes the standalone crafting queue window; works from any character, not just those who have scanned professions

### TradeSkillMaster_AuctionDB (v2.3.10)
**Bug fixes — data encoding guards:**
- Added nil and empty-string guards in `decodeScans()` to prevent corruption when day or market value data fails to decode
- Double-validates decoded `day` value before creating scan entries

**Custom data parsing:**
- Added `DecodeJSON()` function using `gsub()` + `loadstring()` to parse JSON-like app data into Lua tables
- Supports realm/faction data merging with multi-hyphen realm name parsing
- Accepts cross-faction auction data imports within a configurable `MAX_AVG_DAY` time window

**AuxTSMBridge compatibility fix:**
- Added `or 0` guard on `TSM.data[itemID].quantity` in `GetTooltip()` (line 295) — AuxTSMBridge writes synced items with no auction count; TSM's `encode(0)` stores `"~"` which decodes to `nil`, causing `format("%d auctions", nil)` to crash on item hover

### ArkInventory
**Ace3 library xpcall fix (Lua 5.1 / 3.3.5 compatibility):**
- All embedded Ace3 libraries (AceGUI-3.0, AceAddon-3.0, AceTimer-3.0, AceConfigDialog-3.0, AceBucket-3.0, CallbackHandler-1.0) use the `CreateDispatcher(argCount)` pattern — generates closures via `loadstring` that capture arguments before calling `xpcall(call, errorhandler)` with no extra args, working around the 3.3.5 limitation where `xpcall(f, h, ...)` silently drops variadic arguments

**Suppress spurious login warning (`ArkInventory.lua`, `ArkInventoryUpgrades.lua`):**
- Root cause: `GetContainerNumSlots` returns 0 for some bags during the first scan on login (timing race — bags not fully initialised before the scan fires); the addon was logging `WARNING> aborted scan of bag N, location 1 [Bag] size returned was 0` on every login
- `ArkInventory.lua` line 1291: changed default for `option.bugfix.zerosizebag.alert` from `true` to `false` so new characters / fresh profiles start with the warning suppressed
- `ArkInventoryUpgrades.lua` line 1235: changed the upgrade migration that ran on every load from forcing `zerosizebag.alert = true` to `false`, so existing profiles no longer have the warning re-enabled on each reload

**Bank window zone layout fix (SavedVariables — Default profile):**
- Root cause: the bank window (location index `3` per `ArkInventory.Const.Location.Bank = 3`) had no `["bar"]["data"]` table, only `["per"] = 6`, so it displayed 6 unnamed default zones instead of the configured 10
- Fixed `WTF/Account/DEFCON/SavedVariables/ArkInventory.lua`: replaced the minimal bank bar config in the Default profile's `["location"][3]` entry with the full 10-zone definition matching the regular inventory: Junk, Trash, Quest, Consume, Div, Value, DE, Equip, Trinket, Ammo
- Also copied the full category rule table from the bags location so items sort into the same zones in the bank as they do in regular inventory

**Aux / TSM price rule functions (`ArkInventoryRules.lua`):**
- Added aux market price rules using `TSMAPI:GetItemValue(link, "AuxMarket")` (requires AuxTSMBridge) with a direct `aux.faction` history fallback if TSM is absent; gracefully returns `false` when neither addon is loaded
  - `auxpriceunder(copper)` / `apu(copper)` — true if aux market price ≤ threshold
  - `auxpriceover(copper)` / `apo(copper)` — true if aux market price ≥ threshold
- Added TSM arbitrary price-source rules via `TSMAPI:GetItemValue(link, source)`:
  - `tsmpriceunder("source", copper)` / `tpu("source", copper)` — true if named TSM price source ≤ threshold
  - `tsmpriceover("source", copper)` / `tpo("source", copper)` — true if named TSM price source ≥ threshold
  - Works with any registered TSM source key: `"DBMarket"`, `"DBMinBuyout"`, `"AuxMarket"`, `"AuxMinBuyout"`, etc.
- Added `auxovervendor(percent)` / `aov(percent)` — true if aux market price ≥ vendor sell price × (1 + percent/100); e.g. `aov(50)` flags items where AH price is at least 50% above vendor
- Added `deovervendor(copper)` / `dov(copper)` — true if TSM disenchant value exceeds vendor sell price by at least `copper`; uses `TSM:GetDisenchantValue` via AceAddon lookup (no `TSM` global required); returns `false` gracefully if TSM is not loaded
- Added `dedbg()` — debug helper rule that prints vendor price, aux market price, and DE value (with price source) to chat for every item evaluated; always returns false; useful for diagnosing price rule issues
- All functions guard against missing addons (nil checks on `TSMAPI`, `LibStub`, `aux`) — safe to use in an ArkInventory installation without TSM or aux

**Suppress item-cache warning on login (`ArkInventoryStorage.lua`):**
- `GetItemInfo` returns empty strings for type/subtype during the brief post-login window before the client has cached all item data; ArkInventory was printing `WARNING> <temporary> item cache not updated yet` for each affected slot
- Suppressed the warning for the `t == "" and s == ""` case — the slot is correctly handled as `Slot.Type.Unknown` and re-evaluated on the next scan; the "missing translation" warning for genuinely unknown types is preserved

### Magnify-WotLK
**3.3.5 API compatibility:**
- Settings panel uses `InterfaceOptions_AddCategory` / `InterfaceOptionsFrame_OpenToCategory`
- All hooking via `hooksecurefunc()` — no `CreateFromMixins` or `EventRegistry`
- Textures use `CreateTexture()` + `SetTexture()` — no `SetAtlas` or `SetColorTexture`

**Bug fix — zone navigation always landing on the player's current zone:**
- Root cause: `Blizzard_BattlefieldMinimap.lua` registers a `WORLD_MAP_UPDATE` handler that calls `SetMapToCurrentZone()`, overriding any `SetMapZoom()` call made during navigation
- Secondary issue: WoW 3.3.5's game loop runs `OnUpdate` scripts *before* dispatching queued game events, so an `OnUpdate`-based suppression flag clears too early and lets the reset through
- Added `MagnifyNavigateMap()` to replace `WorldMapButton_OnClick` for continent→zone and world→continent clicks: matches `WorldMapFrame.areaName` (set by `UpdateMapHighlight` in `OnUpdate`) against `GetMapZones()` / `GetMapContinents()` and calls `SetMapZoom()` directly, bypassing the game's click handler which does not account for Magnify's scroll frame
- Added `SetMapToCurrentZone` wrapper with a `Magnify_SuppressMapReset` flag; flag is cleared in a `WORLD_MAP_UPDATE` event listener registered after BattlefieldMinimap loads, so our handler fires *after* BattlefieldMinimap's reset call is suppressed
- Added empty `OnClick` handler on `WorldMapButton` to prevent the game's native click event from firing `WorldMapButton_OnClick` a second time after `OnMouseUp` already handled navigation
- `SetDetailFrameScale` (which internally calls `WorldMapFrame_OnEvent`) is now only called when `WorldMapScrollFrame.zoomedIn` is true, preventing spurious map resets on every plain click

### HCBreathBar
- Ported from Classic Era (Interface 11403 → 30300); removed `SOUND_CHANNEL` arg from `PlaySound` (not supported in 3.3.5)
- Default sound changed from numeric ID 12889 (Classic Era only) to `"igQuestComplete"` string, which is valid in 3.3.5
- `self.value` on MirrorTimer frames is already in **seconds** in 3.3.5 (dividing by 1000 caused always-zero display; reverted)
- `MirrorTimer1`/2/3 are plain `Frame` widgets in 3.3.5, not `StatusBar` — `SetStatusBarTexture` doesn't exist on them; styling via child-find approach also failed because the game resets child bar properties each tick
- Final fix: hide the original frame with `SetAlpha(0)` on first BREATH detection; overlay our own fully-controlled `StatusBar` frame anchored to the same position; restore alpha on `MIRROR_TIMER_STOP`
- Minimalist look: flat `WHITE8X8` texture fill, dark semi-transparent trough, no border, wide bar (420×14 px)
- Sound switched to `PlaySoundFile("Sound\\Interface\\AlarmClockWarning1.wav")` — `PlaySound` string form unreliable in 3.3.5; file path is guaranteed present since TBC/WotLK; alert rate doubles when breath < half threshold
- Bar max duration now captured from `MIRROR_TIMER_START` event args rather than `self.maxValue` frame field (field absent/wrong-cased in 3.3.5 causing bar to default to 3-min scale regardless of actual breath pool); normalises ms→s if value > 600
- Font changed from `ARIALN.ttf` 11 px `OUTLINE` to `FRIZQT__.ttf` 13 px `THICKOUTLINE` — heavier outline needed for legibility against the blue fill

### FeralAPFix
- Wraps `GameTooltip:SetHyperlink()` with a nil guard — prevents crash when Ascension's built-in `feral-attack.lua` calls `GetItemInfo(link)` with a nil link triggered by TSM's LibExtraTip tooltip callbacks
- Hook moved to top-level file load (no longer deferred to `PLAYER_LOGIN`) so the guard is in place before TSM or any other addon fires `SetHyperlink(nil)` during the login sequence

### unitscan
- Uses `GetBuildInfo()` build detection (`isWOTLK = build == 30300`) for version-specific UI code
- `LibCompat-1.0` backport library included: provides `IsInRaid()`, `IsInGroup()`, `GetNumGroupMembers()`, `UnitIterator()`, `GetUnitIdFromGUID()` for 3.3.5
- `LibCompat-1.0` uses `pcall` (not `xpcall`) in `QuickDispatch()` — correct for Lua 5.1
- Class color system checks for `CUSTOM_CLASS_COLORS`, falls back to `RAID_CLASS_COLORS`; manually adds missing `colorStr` fields including Death Knight
- `UPDATE()` now returns early on `InCombatLockdown()` before any scan loop runs, preventing `ADDON_ACTION_BLOCKED` spam from `TargetUnit()` being called in combat (taxi/flight early-return was already present but the combat guard only covered `discovered_unit`, not the main scan)

**Feature — combat-safe close button:**
- Close button replaced from `UIPanelCloseButton` to `SecureHandlerClickTemplate` with `SetAttribute("_onclick", "self:GetParent():Hide()")` — allows hiding the popup while in combat lockdown without triggering "Interface action failed" errors

**Feature — dead mob cooldown tracking (`unitscan_dead` SavedVariable):**
- Mobs confirmed dead or corpse are put on a respawn cooldown and skipped from scanning; popup auto-hides when the mob is found dead
- Cooldown is per-mob: reads respawn time in seconds from pfQuest's unit database (`pfDB["units"]["data"][id]["coords"][n][4]`) via a reverse name→ID lookup cache built at `PLAYER_LOGIN`; falls back to `DEAD_COOLDOWN_HOURS` (default 8h) if pfQuest has no data
- `unitscan_dead` stored as `{ t=timestamp, secs=respawn_seconds, from_pfquest=bool }` per mob; persists across sessions via `SavedVariables`; old plain-timestamp entries auto-migrated on load
- Default cooldown changed from 2h to 8h (correct baseline for WotLK outdoor rares); configurable via `/unitscan cooldown <hours>`
- Dead detection moved entirely to `checkTargetDead()` called from `PLAYER_TARGET_CHANGED` and `UNIT_HEALTH` events — removed from the `TargetUnit()`/`forbidden` scan loop which was unreliable (in combat `TargetUnit` doesn't switch target, so `UnitIsDead("target")` read the wrong unit)
- `checkTargetDead()` guards: verifies `UnitName("target")` matches the tracked mob name before acting; skips entirely inside instances (`IsInInstance() ~= "none"`) — instance mobs reset on every run
- `/unitscan cooldowns` — lists all mobs on dead cooldown with time remaining; shows `[pfQ]` tag when timer came from pfQuest database
- `/unitscan cooldown <hours>` — sets the fallback respawn cooldown for mobs not in pfQuest's database
- Chat notifications on death detection ("is dead. Pausing scan for Xh.") and cooldown expiry ("cooldown expired. Resuming scan.")
- `unitscan_defaults` keys backfilled on load to handle SavedVariables from older versions missing new keys (fixes "attempt to perform arithmetic on field 'DEAD_COOLDOWN_HOURS' (a nil value)")

**Feature — pfQuest map icon integration:**
- When a rare is detected dead, its `/db track rares` map icon is immediately removed via `pfMap:DeleteNode("TRACK_RARES", name)` + `pfMap:UpdateNodes()`
- `pfMap:UpdateNodes` is hooked so the icon stays hidden on every map open/refresh while cooldown is active; restores automatically when cooldown expires
- All pfMap calls nil-guarded — silently no-ops if pfQuest is not installed or rares tracking is disabled

**Feature — instance dismiss cooldown:**
- Clicking the X button (or right-clicking) the popup while inside any instance applies a 1 hour cooldown so the same mob won't alert again for the remainder of the session
- Implemented via `PreClick` on the close button (fires before the secure `_onclick` hide, so `button:GetText()` is still valid) and `PostClick` on the main button for the right-click path
- Only triggers inside instances (`IsInInstance() ~= "none"`); open-world dismissals are unaffected

### pfQuest-epoch
**New feature — Rares/Chests toggle buttons on the WorldMap (`pfQuest-worldmap.lua`):**
- Two small toggle buttons (76×16 px, custom backdrop) anchored inside `WorldMapPositioningGuide` top-right, below the close/arrow buttons, with no gap between them
- **Rares** button and **Chests** button each toggle their respective `pfDatabase:TrackMeta()` tracking on/off with a single click; label and backdrop colour update to reflect current state (green = ON, dark = OFF)
- Tooltip on hover shows current state and equivalent slash command (`/db track rares` / `/db track chests`)
- Syncs with slash-command state changes via `WORLD_MAP_UPDATE` event (safe — does not hook `WorldMapFrame_Update` or `SetScript OnShow`, both of which break `SetupFullscreenScale` in 3.3.5)
- Buttons use `SetFrameStrata("DIALOG")` + `SetFrameLevel(100)` so they remain clickable in windowed map mode

- Epoch-specific NPC/quest database layered over pfQuest-wotlk via `patchtable()` merge system
- `overwrites.lua` removes content not present on Epoch (Silithus NPCs, TBC quest givers, Zul'Aman island)
- Version checking via `GetAddOnMetadata()` with addon messaging for update notifications
- Update notifications (`pfQuest-epoch.lua`, `pfQuest-updater.lua`) now gated behind `pfQuest_config["updatenotify"]` — default off; only print if config key is explicitly `"1"`

### pfQuest-wotlk
- Added `"Cut-Out Range (yards, 0=always)"` text field to `pfQuest_defconfig` (config key `cutoutminimaprange`, default `"0"`); when non-zero, minimap cut-out icons are only rendered within that yard radius of the player — avoids icon clutter at map edges
- `pfMap:UpdateNode` gains a `yards_distance` parameter; `UpdateMinimap` converts pixel distance to yards (`distance * mapZoom / drawlayer:GetWidth()`) and passes it through for the range check
- Added `"Show Update Notifications"` checkbox to `pfQuest_defconfig` (config key `updatenotify`, default `"0"` / off); controls whether pfQuest-epoch version-available messages appear in chat
- Multi-client compatibility layer (`compat/client.lua`): detects build version and maps API differences between Vanilla/TBC/WotLK
- `string.gmatch or string.gfind` fallback for Lua 5.0 vs 5.1
- `mod or math.mod` fallback for math function rename
- Quest frame name mappings for 3.3 renames (`QuestLogQuestTitle` → `QuestInfoTitleHeader`, etc.)
- `QuestWatchFrame` vs `WatchFrame` handled per client version
- Item link suffix format differs per client (`":0:0:0"` vs `":0:0:0:0:0:0:0:0"`)
- Wowhead database URL selected per client (wotlk/tbc/classic)

**Bug fixes — quest log raw override removal (`quest.lua`):**
- Replaced raw `AbandonQuest = function()` global override with `QuestLogAbandonButton:HookScript("OnClick")` — the override was calling `GetAbandonQuestName()` at confirm time, which could return a stale/wrong quest if another addon (e.g. Leatrix auto-quest scan) called `SelectQuestLogEntry()` while the confirmation popup was open; hooking the button captures the name at click time before any event can shift the selection
- Replaced raw `QuestLog_Update = function()` global override with `hooksecurefunc("QuestLog_Update", ...)` — the raw replacement was creating a tainted version of this function, which on 3.3.5 can prevent `QuestLogAbandonButton` (controlled by `QuestLog_Update`'s call chain) from responding to clicks
- Replaced raw `QuestLogTitleButton_OnClick = function()` global override with `hooksecurefunc("QuestLogTitleButton_OnClick", ...)` for the same taint reason

### Postal
**Open All — reliability and speed improvements:**
- Fixed `updateFrame` event handler: on `MAIL_INBOX_UPDATE`, the timer is now accelerated to 0.05 s instead of calling `ProcessNext()` directly; calling `TakeInboxItem` inside an event handler chain causes the request to be silently dropped by the client on Ascension, so deferring to the timer avoids that race
- Added `stuckTime` tracking: if `CountItemsAndMoney()` reports no change for more than 5 real seconds after a `TakeInboxItem` call, the current mail is skipped and processing continues with the next one (prevents permanent "In Progress" hangs)

**Open All — automatic mailbox pagination:**
- After exhausting the currently shown mails, `refreshFrame` now calls `CheckInbox()` and waits for the resulting `MAIL_INBOX_UPDATE` event before reading inbox counts; this avoids reading stale data that was a problem with the previous pure-timer approach
- Initial refresh delay reduced from 5 s to 2 s; an 8 s fallback timer fires a second `CheckInbox()` if `MAIL_INBOX_UPDATE` never arrives
- Once a full batch (50 mails or all remaining mail) is confirmed, Open All resumes automatically after 1 s

### Aux-addon (Post tab, Auctions tab & Tooltip)
**New feature — configurable history decay (`core/history.lua`, `core/slash.lua`):**
- Hardcoded `0.99` decay base replaced with a `get_decay()` / `set_decay(v)` pair backed by `aux.account.history_decay` SavedVariable; default changed to `0.75` (≈3-day half-life vs the original ~99-day half-life) so prices respond to market moves in days rather than months
- `/aux history decay <0.01–0.99>` slash command sets the decay live; `set_decay` flushes the value cache so the next price lookup recalculates immediately; current value shown in `/aux` help output
- `M.get_decay` exposed on the module so `slash.lua` can read it without a circular require

**New feature — `% Hist. Value` column in Auctions and Bids tabs (`gui/auction_listing.lua`):**
- Added sortable `% Hist. Value` column to both the Auctions tab and the Bids tab showing each listing's buyout (or bid) as a percentage of the Aux historical market value
- Reused the existing `record_percentage` / `percentage_historical` helpers already present in the file; no new logic needed
- Narrowed `High Bidder` (0.21→0.13), `Seller` (0.13→0.09), and `Status` (0.115→0.075) columns to make room without breaking total width

**Bug fix — tooltip crash "Invalid quest item in SetQuestLogItem" (`core/tooltip.lua`):**
- Hook wrapper called the original `SetQuestLogItem` (and all other hooked tooltip methods) unconditionally; when `LibExtraTip` called it with a stale/invalid quest item, the WoW API threw before returning, crashing the whole chain
- Fixed by wrapping the original call in `pcall` — on failure the error is caught silently and the custom `extend_tooltip` logic is skipped (correct, nothing valid to show); on success everything proceeds as before

**Bug fix — deposit always showing 1 silver (`tabs/post/core.lua`):**
- `unit_vendor_price()` works by temporarily slotting the item into the auction sell slot; in 3.3.5 this often returns `0` or fails silently, bypassing the `GetItemInfo` fallback (which only ran on `nil`, not `0`) and falling through to the `100 * stack_count` minimum
- Fixed by flipping priority: `GetItemInfo(item_id)` return value 11 (vendor sell price) is checked first since it is always reliable once the item is cached; the scanned `unit_vendor_price` is only used as a fallback when `GetItemInfo` returns nothing

**Bug fix — Buyout button never executing the bid:**
- `PlaceAuctionBid` must be called from a hardware event (button click), not from an `OnUpdate`/scan-thread callback; calling it from `on_auction` silently did nothing
- Replaced the old single-click flow with a two-click state machine (`idle → searching → found → idle`) in a `do`-block with private state (`buyout_state`, `buyout_index`, `buyout_price_total`)
- First click: validates selection, starts a list scan to locate the exact auction; sets state to `searching` and disables button
- On match found: stores auction index + total price, sets state to `found`, re-enables button with "click again to confirm" status
- Second click: IS the hardware event — safely calls `place_bid` and resets state to `idle`
- `reset_buyout_state()` called in `update_item()` to clear stale state when switching items

**Bug fix — Unit Starting Price showing inflated value after auto-selection:**
- Root cause: `bid_selection` was auto-selected to the cheapest bid row; `undercut()` with `stack=true` computes `ceil(unit_price × record.stack_size) / slider_stack_size`, producing e.g. 250g start price for a 5-stack at 50g/item when slider=1
- Fix: removed `bid_selection` auto-selection entirely from `update_auction_listing`; `bid_selection` is now only set when the user manually clicks a bid row
- Both start price and buyout price now derive from `buyout_selection` (same record, same stack size), so `unit_start_price ≤ unit_buyout_price` is always satisfied

**Bug fix — price_update running one frame before auto-selections were visible:**
- `price_update()` was called before `update_auction_listings()` in `on_update()`, so auto-selections from the current frame weren't yet in `buyout_selection` when prices were computed
- Fix: reordered `on_update()` — `update_auction_listings()` first, then `price_update()`

**New feature — manual price override:**
- Typing a custom price in the Unit Starting Price or Unit Buyout Price edit boxes was immediately overwritten on the next frame by the auto-selection logic
- Added `user_price_override` flag (private `do`-block with `get_user_price_override` / `set_user_price_override`)
- `char` handlers on both price inputs now set `user_price_override = true`; cleared on item switch (`update_item`) or explicit refresh (`refresh_entries`)
- `update_auction_listing` skips buyout auto-selection when `user_price_override` is true

**New feature — inventory list auto-scroll to selected item:**
- After posting or pressing Next, the newly selected item could be off-screen, requiring manual scrollbar use
- Added `M.scroll_to(item_listing, target_record)` to `gui/item_listing.lua`: finds item index, checks if already visible, and calls `scroll_frame:SetVerticalScroll(offset * ROW_HEIGHT)` only when needed
- `update_inventory_listing` wrapped in a `do`-block with `last_scroll_target` tracking; scrolls only when `selected_item` changes, preventing scroll disruption on same-item refreshes

**Bug fix — Auctions tab selection reset after cancelling an auction:**
- `CancelAuction()` fires `AUCTION_OWNED_LIST_UPDATE` → `scan_auctions()` → `wipe(auction_records)` → `SetDatabase(empty)` → `UpdateRowInfo()` calls `SetSelectedRecord(nil)`, destroying the selection before the rescan completes
- Fix in `tabs/auctions/core.lua`: save `prev_item_key` and `prev_name` from `listing.selected` before wiping; after `update_listing()` in `on_complete`, restore selection with three-tier fallback:
  1. Same `item_key` still has auctions → stay on it
  2. Item is gone → pick next item alphabetically by name
  3. Nothing after it → fall back to first remaining auction

**New feature — auto-advance to next item after posting:**
- After clicking Post, the callback now builds a sorted, filtered inventory list and selects the first item alphabetically after the one just posted
- Fallback chain: stay on same item if it still has quantity remaining → take the last item if nothing comes after alphabetically
- `select_next_item()` function added for the new **Next** button, with wrap-around (goes back to first item after the last)

**New feature — Next button:**
- New `Next` button in the Post tab toolbar advances to the next item in the inventory list (alphabetical order, wraps around)
- Enabled whenever inventory contains at least one auctionable item

**New feature — buyout auto-select lowest price:**
- After a scan completes, the buyout listing now automatically selects the first non-historical-value row (i.e. the lowest-priced real auction) so prices are immediately ready for undercutting without requiring a manual click
- Auto-selection is skipped if `user_price_override` is true (user has manually typed a price)

**Bug fix — deposit always showing 1s:**
- Deposit rate was 5%/25% — corrected to 15%/75% matching actual WoW 3.3.5 faction/neutral AH rates
- Duration dropdown stores enum integers (1/2/3), not hours; fixed by mapping DURATION_12/24/48 → 12/24/48 hours before computing `duration_factor = hours / 12`; previously dividing by 120 produced a near-zero multiplier that collapsed the deposit to the 1s minimum floor
- Deposit calculation now tries `select(11, GetItemInfo(item_id))` as primary vendor price source and falls back to `unit_vendor_price`; `GetAuctionSellItemInfo` is unreliable on Epoch

**Bug fix — default stack count now half of total quantity:**
- When selecting an item, stack size defaults to 1 and stack count defaults to `floor(total / 2)` (minimum 1), so half the bag quantity is queued by default instead of 1

### !!!ClassicAPI (game-shipped library)
**Bug fix — `SetAtlas` hard-error on unknown atlas name (`Util/SharedExtendedMethods.lua`):**
- `Method_SetAtlas()` called `Assert(Atlas, "SetAtlas: Atlas named X does not exist")` when a requested atlas wasn't in `ATLAS_INFO_STORAGE`; `Ascension_HelpUI` (a built-in game UI addon) requests `transmog-no-item` which only exists in retail — this caused a hard Lua error every time the Help menu was opened, crashing the entire layout generator
- Fixed by replacing the `Assert` with a silent `if not Atlas then return end` — the icon simply doesn't render instead of erroring; matches the expected graceful behaviour when an atlas is unavailable on the 3.3.5 client

### Whats-Training-Epoch
**Bug fix — "Now available at trainer" messages shown at level 60 (`Announce.lua`):**
- Login announcement and level-up announcement both fire at level 60 even though there are no more trainable levels beyond cap
- Added `UnitLevel("player") < 60` guard to the login delayed-announcement scheduler; added early `return` in the `PLAYER_LEVEL_UP` handler when new level ≥ 60
- `/wte test` command is unaffected and still works for manual testing

### TitanGoldTracker
- Uses `UIDropDownMenu_AddButton()` for context menus (not modern `MenuUtil`)
- Uses Ace3 timer wrappers (`ScheduleRepeatingTimer`, `CancelTimer`) — no `C_Timer` dependency
- Uses `hooksecurefunc()` for safe function hooking
- All frame templates are standard 3.3.5 Titan Panel templates
- **Cross-faction gold:** `GetTooltipText`, `FindGold`, and `TotalGold` now match all characters on the same realm regardless of faction; `server` key is now just the realm name and comparison uses `string.find(charserver, server, 1, true) == 1` to match any `Realm::Alliance` or `Realm::Horde` entry; tooltip header updated to show "All Factions"
