# Magnify-WotLK (v1.0)

Originally by rissole. Modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### API compatibility
- Settings panel uses `InterfaceOptions_AddCategory` / `InterfaceOptionsFrame_OpenToCategory`
- All hooking via `hooksecurefunc()` — no `CreateFromMixins` or `EventRegistry`
- Textures use `CreateTexture()` + `SetTexture()` — no `SetAtlas` or `SetColorTexture`

### Bug fix — zone navigation always landing on the player's current zone
- Root cause: `Blizzard_BattlefieldMinimap.lua` registers a `WORLD_MAP_UPDATE` handler that calls `SetMapToCurrentZone()`, overriding any `SetMapZoom()` call made during navigation
- Secondary issue: WoW 3.3.5's game loop runs `OnUpdate` scripts *before* dispatching queued game events, so an `OnUpdate`-based suppression flag clears too early
- Added `MagnifyNavigateMap()` to replace `WorldMapButton_OnClick` for continent→zone and world→continent clicks
- Added `SetMapToCurrentZone` wrapper with a `Magnify_SuppressMapReset` flag; flag is cleared in a `WORLD_MAP_UPDATE` event listener registered after BattlefieldMinimap loads
- Added empty `OnClick` handler on `WorldMapButton` to prevent the native click event from firing a second time
- `SetDetailFrameScale` is now only called when `WorldMapScrollFrame.zoomedIn` is true

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
