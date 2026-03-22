# unitscan — Changelog

## Ascension/Epoch Modifications

### Core compatibility
- Uses `GetBuildInfo()` build detection (`isWOTLK = build == 30300`) for version-specific UI code
- `LibCompat-1.0` backport library included: provides `IsInRaid()`, `IsInGroup()`, `GetNumGroupMembers()`, `UnitIterator()`, `GetUnitIdFromGUID()` for 3.3.5
- `LibCompat-1.0` uses `pcall` (not `xpcall`) in `QuickDispatch()` — correct for Lua 5.1
- Class color system checks for `CUSTOM_CLASS_COLORS`, falls back to `RAID_CLASS_COLORS`; manually adds missing `colorStr` fields including Death Knight
- `UPDATE()` now returns early on `InCombatLockdown()` before any scan loop runs, preventing `ADDON_ACTION_BLOCKED` spam

### Feature — combat-safe close button
- Close button replaced from `UIPanelCloseButton` to `SecureHandlerClickTemplate` with `SetAttribute("_onclick", "self:GetParent():Hide()")` — allows hiding the popup while in combat lockdown

### Feature — dead mob cooldown tracking (`unitscan_dead` SavedVariable)
- Mobs confirmed dead are put on respawn cooldown and skipped from scanning; popup auto-hides when the mob is found dead
- Reads respawn time from pfQuest's unit database (`pfDB["units"]["data"][id]["coords"][n][4]`) via a reverse name→ID lookup cache; falls back to `DEAD_COOLDOWN_HOURS` (default 8h)
- `unitscan_dead` stored as `{ t=timestamp, secs=respawn_seconds, from_pfquest=bool }` per mob; old plain-timestamp entries auto-migrated on load
- Dead detection moved to `checkTargetDead()` called from `PLAYER_TARGET_CHANGED` and `UNIT_HEALTH` events
- `checkTargetDead()` guards: verifies `UnitName("target")` matches the tracked mob; skips inside instances
- Chat notifications on death detection and cooldown expiry
- `/unitscan cooldowns` — lists all mobs on dead cooldown with time remaining; shows `[pfQ]` tag when timer came from pfQuest
- `/unitscan cooldown <hours>` — sets the fallback respawn cooldown

### Feature — pfQuest map icon integration
- When a rare is detected dead, its `/db track rares` map icon is immediately removed via `pfMap:DeleteNode("TRACK_RARES", name)` + `pfMap:UpdateNodes()`
- `pfMap:UpdateNodes` is hooked so the icon stays hidden on every map refresh while cooldown is active; restores automatically when cooldown expires
- All pfMap calls nil-guarded — silently no-ops if pfQuest is not installed

### Feature — instance dismiss cooldown
- Clicking the X button (or right-clicking) the popup while inside any instance applies a 1-hour cooldown
- Implemented via `PreClick` on the close button and `PostClick` on the main button for the right-click path
- Only triggers inside instances; open-world dismissals are unaffected
