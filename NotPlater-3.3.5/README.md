# NotPlater-3.3.5

A feature-rich nameplate addon with threat coloring, ported and bug-fixed for **WoW 3.3.5a (Ascension/Epoch)**.

## Changes from the original

### Bug fixes
- **"Usage: UnitDetailedThreatSituation" error** — added `UnitExists()` guards before all `UnitDetailedThreatSituation` calls; compound unit tokens like `"pet-target"` and stale units no longer cause hard Lua errors in combat
- **Login crash "table index is nil"** — `UnitGUID("player")` returns nil during early events before `PLAYER_LOGIN`; all GUID calls are now nil-checked before use as table keys
- **"High Threat" color never shown** — `lastThreat` was keyed by volatile unit-ID strings which change between calls; now keyed by stable GUID via `healthFrame.lastUnitGuid`
- **`MouseoverThreatCheck` ignoring its `guid` parameter** — always set `lastUnitMatch = "mouseover"` and discarded the passed GUID; now also sets `lastUnitGuid = guid`
- **`tgetn(group)` always returning 0** — `group` is a GUID-keyed hash table; replaced `table.getn` with a `groupSize` counter
- **`ThreatComponentsOnShow` crash on login ("Font not set")** — `SetText("")` called before font was set; guarded with `GetFont()` check

### New features
- **Solo play / Hunter pet threat** — threat path now runs for solo players; Hunter pet threat correctly shown using `UnitDetailedThreatSituation` status field fallback when not in a party or raid

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
