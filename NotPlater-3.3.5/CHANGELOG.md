# NotPlater-3.3.5 — Changelog

## Ascension/Epoch Port

### Bug fix — "Usage: UnitDetailedThreatSituation" error (`modules/threat-3.3.5.lua`)
- `GetThreat` and `GetMaxThreatOnTarget` called `UnitDetailedThreatSituation` unconditionally; compound unit tokens like `"pet-target"` and stale/non-existent units cause the API to throw a hard Lua error in combat
- Fixed by adding `UnitExists()` guards in both functions before calling the API; invalid units return `nil`/`0` safely

### Bug fix — login crash "table index is nil" (`modules/threat-3.3.5.lua:80`)
- `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE` are called from `OnInitialize` before `PLAYER_LOGIN`, at which point `UnitGUID("player")` returns nil — using nil as a table key is a hard Lua error
- Fixed by storing all `UnitGUID()` calls in locals and nil-checking before assigning

### Bug fix — "High Threat" color never displayed (`modules/threat-3.3.5.lua`)
- `lastThreat` was keyed by volatile unit-ID strings (`"mouseover"`, `"party1-target"`, etc.) which change between calls, so the threat-trajectory comparison always saw `nil` and skipped the High Threat (c2) state entirely
- Fixed by adding `healthFrame.lastUnitGuid` (stable GUID) stored at all three match sites; `lastThreat` now keyed and read by GUID

### Bug fix — `MouseoverThreatCheck` ignored its `guid` parameter
- Was always setting `lastUnitMatch = "mouseover"` and discarding the passed-in `guid`; now also sets `lastUnitGuid = guid`

### Bug fix — `tgetn(group)` on a hash table always returned 0
- `group` is keyed by GUID (hash table), so `table.getn` always returned 0
- Replaced with `groupSize` counter incremented inside the existing loop

### Bug fix — `ThreatComponentsOnShow` crash on login ("Font not set")
- `SetText("")` was called on FontStrings before `ConfigureThreatComponents` had set their font
- Fixed by guarding with `if healthFrame.threatDifferentialText:GetFont() then`

### Feature — solo play support (Hunter pet threat)
- `PARTY_MEMBERS_CHANGED` now always builds `self.party`, always including `"player"` and `"pet"` if present
- Threat path now runs for solo players; `UnitDetailedThreatSituation` status field used as fallback when not in a group
