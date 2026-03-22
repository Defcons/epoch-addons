# TradeSkillMaster_Crafting — Changelog

## v2.5.2 — Ascension/Epoch Modifications

### New feature — Vellum support for enchanting crafts
- Added `VellumInfo.lua`: lookup table mapping enchanting spell IDs to the correct vellum item IDs (38682, 37602, 39349, 39350, 43145, 43146)
- Added `CheapestVellum()` function: automatically substitutes a lower-tier vellum with Vellum III when it's cheaper; guards against `nil` returns from `GetItemInfo()`
- Vellum cost integrated into crafting cost display and tooltip breakdown
- `OnEnable()` migration routine: fixes legacy vellum item string formatting in saved DB

### Crafting queue — intermediate craft flattening overhaul (`Queue.lua`)
- Added `FindIntermediateSpellID(itemString)` helper: finds the best spell for crafting an item as an intermediate; tries cost-based `GetLowestCraftPrices` first, falls back to direct `craftReverseLookup` scan when pricing data is absent; prefers non-cooldown crafts
- `GetIntermediateCrafts`: intermediates are now always expanded whenever a known craft exists, not only when TSM pricing data is available
- `HasLoop`: updated to use `FindIntermediateSpellID` so loop detection mirrors the new expansion logic
- Bug fix: `usedMats` re-add at end of `GetQueue()` now skips zero-quantity entries — previously an intermediate craft with zero inventory would be re-inserted with `quantity = 0`, appearing in the materials list as "Need 0 / Total 0"
- Materials calculation reverted to always use full `data.queued` (removed an earlier `effectiveQueued` reduction that caused materials to show Total = 0 when result items were stocked on any character)

### Crafting queue — alt-stock awareness (`CraftingGUI.lua`)
- Queue display now shows `(X stocked, craft Y)` annotation next to each craft name when `GetTotalQuantity` detects existing stock across all characters
- Bug fix (`UpdateQueue`): `TSM.db.factionrealm.tradeSkills[UnitName("player")]` nil-guarded with `or {}`; previously crashed when a character that had never scanned professions opened the queue panel

### New slash command — `/tsm queue` (`TradeSkillMaster_Crafting.lua`)
- Added `/tsm queue` slash command that opens/closes the standalone crafting queue window from any character
