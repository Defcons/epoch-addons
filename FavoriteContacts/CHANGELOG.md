# FavoriteContacts — Changelog

> Originally by lqpbgjuc & eXochron. Ported from retail 12.0 to 3.3.5a for Ascension/Epoch by Defcon — version history below is independent from the original addon.

## v1.0 — Ported from Retail 12.0 to WoW 3.3.5a

### API compatibility fixes
- Replaced `C_AddOns.GetAddOnMetadata` → `GetAddOnMetadata`
- Replaced `Settings.RegisterAddOnCategory` → `InterfaceOptions_AddCategory`
- Replaced `Settings.RegisterCanvasLayoutCategory` → standard options frame registration
- Added double-call of `InterfaceOptionsFrame_OpenToCategory()` to work around 3.3.5 panel focus bug
- Guarded `slider:SetObeyStepOnDrag()` — not available in 3.3.5

### UI framework compatibility (XML / Lua)
- Replaced `parentKey` attribute (retail-only) throughout all XML with `name="$parentXxx"` naming; all child access updated to `_G["ParentNameXxx"]` pattern
- Replaced `relativeKey` anchor references with explicit `relativeTo="globalName"` in all `<Anchor>` elements
- Removed `inherits="SelectionFrameTemplate"` (retail-only); `OkayButton` and `CancelButton` created programmatically via `UIPanelButtonTemplate`
- `UIRadioButtonTemplate` child FontString: `parentKey` is ignored in 3.3.5; buttons explicitly named `FavoriteContactsRadioButton1…N` and `.text` assigned via `_G[name.."Text"]`
- Replaced `SetSize(w,h)` → separate `SetWidth()` / `SetHeight()` calls throughout
- Removed 5th `CreateFrame` argument (not supported in 3.3.5)
- `FauxScrollFrame_GetOffset()` returns nil before first scroll in 3.3.5 — added `or 0` at both call sites
- Removed the `ListScrollFrameTemplate` ScrollFrame from the icon picker — 56 icons fit in 8×7 slots without scrolling; `scrollOffset` hardcoded to `0`

### Contact button container (`ContactContainer.lua`)
- Added dark `SetBackdrop` with `SetBackdropColor(0,0,0,0.85)`; grey border when locked, gold border when unlocked
- `SetMovable(true)` + drag support; position saved to `settings.posX`/`settings.posY` via `GetLeft()`/`GetTop()` on `DragStop`
- Right-click toggles `settings.locked`; border colour updates immediately
- Removed all `OpenMailFrame:ClearAllPoints()`/`SetPoint()` calls — repositioning mail child frames externally breaks 3.3.5 mail UI layout

### Settings (`Settings.lua`)
- Default `scale` changed from `"AUTO"` to `0.75`
- Added `locked = true`, `posX = false`, `posY = false` to `defaultSettings` and `ResetUISettings`

### Icon palette (`EditPopup.lua`)
- Replaced all `ClassIcon_*` and unreliable `ability_*`/`spell_*` icons with confirmed-working `inv_*` item icons
- Race icons use `achievement_character_*` (WotLK achievement icons, confirmed in this client)
- Profession icons use `Trade_*` and `inv_*` prefixes
- Added type guards on saved position coordinates (`type(posX) == "number"`)
