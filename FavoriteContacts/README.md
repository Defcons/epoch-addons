# FavoriteContacts (v2.13.1)

A mailbox contacts addon ported from **retail WoW 12.0** to **WoW 3.3.5a (Ascension/Epoch)**. Adds a persistent favourite contacts bar to the mailbox so you can address mail with a single click.

## Changes / Porting Notes

### API compatibility
- Replaced `C_AddOns.GetAddOnMetadata` → `GetAddOnMetadata`
- Replaced `Settings.RegisterAddOnCategory` / `RegisterCanvasLayoutCategory` → `InterfaceOptions_AddCategory`
- Double-call of `InterfaceOptionsFrame_OpenToCategory()` to work around 3.3.5 panel focus bug
- Guarded `slider:SetObeyStepOnDrag()` — not available in 3.3.5

### UI framework compatibility
- Replaced all `parentKey` XML attributes with `name="$parentXxx"` and `_G["ParentNameXxx"]` access
- Replaced `relativeKey` anchor references with explicit `relativeTo="globalName"`
- Removed `inherits="SelectionFrameTemplate"` (retail-only); buttons created via `UIPanelButtonTemplate`
- `UIRadioButtonTemplate` children explicitly named and accessed via `_G`
- Replaced `SetSize(w,h)` → separate `SetWidth()` / `SetHeight()` calls
- Removed unsupported 5th `CreateFrame` argument
- `FauxScrollFrame_GetOffset()` guarded with `or 0` (returns nil before first scroll in 3.3.5)
- Icon picker simplified to 56 icons in 8×7 grid (no scroll frame needed)

### UI improvements
- Contact container has dark backdrop with gold border when unlocked, grey when locked
- Right-click toggles lock state; position saved and restored across sessions
- Removed mail frame repositioning calls that broke 3.3.5 mail UI layout
- Icon palette uses confirmed-working 3.3.5 icons (`inv_*`, `achievement_character_*`, `Trade_*`)

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
