# Addon Changelog — Ascension (WoW 3.3.5a / Interface 30300)

All addons modified or created with Claude Code assistance for the Ascension private server.

---

## NEW ADDONS (Created from scratch)

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
- **Fix 2 — Quest abandon:** Captures quest log index before abandon popup opens; re-selects correct quest when popup is accepted, preventing index shift from other addons (e.g. Leatrix)
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

**Crafting queue — intermediate craft flattening overhaul (`Queue.lua`):**
- Added `FindIntermediateSpellID(itemString)` helper: finds the best spell for crafting an item as an intermediate; tries cost-based `GetLowestCraftPrices` first, falls back to direct `craftReverseLookup` scan when pricing data is absent (e.g. items with no AH data on the private server); prefers non-cooldown crafts
- `GetIntermediateCrafts`: replaced the old `craftCost and lowestCost and craftCost <= lowestCost` gate — intermediates are now always expanded whenever a known craft exists, not only when TSM pricing data is available; uses `FindIntermediateSpellID`
- `HasLoop`: updated to use `FindIntermediateSpellID` so loop detection mirrors the new expansion logic
- Bug fix: `usedMats` re-add at end of `GetQueue()` now skips zero-quantity entries; previously an intermediate craft with zero inventory would be re-inserted into the materials table with `quantity = 0`, causing it to appear in the materials list as "Need 0 / Total 0"
- Materials calculation reverted to always use full `data.queued` (removed an earlier `effectiveQueued` reduction that caused materials to show Total = 0 when result items were stocked on any character)

**Crafting queue — alt-stock awareness (`CraftingGUI.lua`):**
- Queue display now shows `(X stocked, craft Y)` annotation next to each craft name when `GetTotalQuantity` detects you already have some of the result item across all characters; correctly reduces the "effective crafts needed" count in the annotation without affecting the materials list
- Bug fix (`UpdateQueue`): `TSM.db.factionrealm.tradeSkills[UnitName("player")]` nil-guarded with `or {}`; previously crashed when a character that had never scanned professions with TSM opened the queue panel (e.g. a bank alt opening First Aid)

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
- Sound uses `PlaySound("igQuestComplete")` — valid 3.3.5 sound name; alert rate doubles when breath < half threshold

### FeralAPFix
- Wraps `GameTooltip:SetHyperlink()` with a nil guard — prevents crash when Ascension's built-in `feral-attack.lua` calls `GetItemInfo(link)` with a nil link triggered by TSM's LibExtraTip tooltip callbacks
- Hook moved to top-level file load (no longer deferred to `PLAYER_LOGIN`) so the guard is in place before TSM or any other addon fires `SetHyperlink(nil)` during the login sequence

### unitscan
- Uses `GetBuildInfo()` build detection (`isWOTLK = build == 30300`) for version-specific UI code
- `LibCompat-1.0` backport library included: provides `IsInRaid()`, `IsInGroup()`, `GetNumGroupMembers()`, `UnitIterator()`, `GetUnitIdFromGUID()` for 3.3.5
- `LibCompat-1.0` uses `pcall` (not `xpcall`) in `QuickDispatch()` — correct for Lua 5.1
- Class color system checks for `CUSTOM_CLASS_COLORS`, falls back to `RAID_CLASS_COLORS`; manually adds missing `colorStr` fields including Death Knight
- `UPDATE()` now returns early on `InCombatLockdown()` before any scan loop runs, preventing `ADDON_ACTION_BLOCKED` spam from `TargetUnit()` being called in combat (taxi/flight early-return was already present but the combat guard only covered `discovered_unit`, not the main scan)

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

### Postal
**Open All — reliability and speed improvements:**
- Fixed `updateFrame` event handler: on `MAIL_INBOX_UPDATE`, the timer is now accelerated to 0.05 s instead of calling `ProcessNext()` directly; calling `TakeInboxItem` inside an event handler chain causes the request to be silently dropped by the client on Ascension, so deferring to the timer avoids that race
- Added `stuckTime` tracking: if `CountItemsAndMoney()` reports no change for more than 5 real seconds after a `TakeInboxItem` call, the current mail is skipped and processing continues with the next one (prevents permanent "In Progress" hangs)

**Open All — automatic mailbox pagination:**
- After exhausting the currently shown mails, `refreshFrame` now calls `CheckInbox()` and waits for the resulting `MAIL_INBOX_UPDATE` event before reading inbox counts; this avoids reading stale data that was a problem with the previous pure-timer approach
- Initial refresh delay reduced from 5 s to 2 s; an 8 s fallback timer fires a second `CheckInbox()` if `MAIL_INBOX_UPDATE` never arrives
- Once a full batch (50 mails or all remaining mail) is confirmed, Open All resumes automatically after 1 s

### Aux-addon (Post tab & Auctions tab)
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

### TitanGoldTracker
- Uses `UIDropDownMenu_AddButton()` for context menus (not modern `MenuUtil`)
- Uses Ace3 timer wrappers (`ScheduleRepeatingTimer`, `CancelTimer`) — no `C_Timer` dependency
- Uses `hooksecurefunc()` for safe function hooking
- All frame templates are standard 3.3.5 Titan Panel templates
- **Cross-faction gold:** `GetTooltipText`, `FindGold`, and `TotalGold` now match all characters on the same realm regardless of faction; `server` key is now just the realm name and comparison uses `string.find(charserver, server, 1, true) == 1` to match any `Realm::Alliance` or `Realm::Horde` entry; tooltip header updated to show "All Factions"
