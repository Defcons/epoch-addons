# TradeSkillMaster_Crafting (v1.1)

Originally based on TSM_Crafting by Sapu94 & Bart39. Heavily modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### New feature — Vellum support for enchanting crafts
- Automatically adds the correct vellum cost to enchanting crafts
- Substitutes a lower-tier vellum with Vellum III when it is cheaper
- Vellum cost shown in crafting cost display and tooltip breakdown
- Supports all vellum tiers (item IDs: 38682, 37602, 39349, 39350, 43145, 43146)

### Crafting queue — intermediate craft flattening overhaul
- Intermediates are now always expanded whenever a known craft exists, not only when TSM pricing data is available (fixes private-server items with no AH data)
- `FindIntermediateSpellID()` tries cost-based pricing first, falls back to direct `craftReverseLookup` scan; prefers non-cooldown crafts
- Loop detection (`HasLoop`) updated to mirror the new expansion logic

### Bug fixes
- Zero-quantity intermediate crafts no longer appear in the materials list as "Need 0 / Total 0"
- Materials calculation always uses full `data.queued` — removing an earlier reduction that caused Total = 0 when result items were stocked on any character

### Crafting queue — alt-stock awareness
- Queue display shows `(X stocked, craft Y)` annotation when you already have some of the result item across all characters
- `UpdateQueue` nil-guarded for characters who have never scanned professions with TSM

### New slash command — `/tsm queue`
- Opens/closes the standalone crafting queue window from any character
