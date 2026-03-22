# ArkInventory — Changelog

## Ascension/Epoch Modifications

### Ace3 library xpcall fix (Lua 5.1 / 3.3.5 compatibility)
- All embedded Ace3 libraries (AceGUI-3.0, AceAddon-3.0, AceTimer-3.0, AceConfigDialog-3.0, AceBucket-3.0, CallbackHandler-1.0) use the `CreateDispatcher(argCount)` pattern — generates closures via `loadstring` that capture arguments before calling `xpcall(call, errorhandler)` with no extra args, working around the 3.3.5 limitation where `xpcall(f, h, ...)` silently drops variadic arguments

### Suppress spurious login warning (`ArkInventory.lua`, `ArkInventoryUpgrades.lua`)
- Root cause: `GetContainerNumSlots` returns 0 for some bags during the first scan on login (timing race)
- `ArkInventory.lua` line 1291: changed default for `option.bugfix.zerosizebag.alert` from `true` to `false`
- `ArkInventoryUpgrades.lua` line 1235: upgrade migration now forces `zerosizebag.alert = false` so existing profiles no longer have the warning re-enabled on each reload

### Bank window zone layout fix (SavedVariables — Default profile)
- Root cause: bank window (location index `3`) had no `["bar"]["data"]` table, displaying 6 unnamed default zones instead of the configured 10
- Fixed Default profile's `["location"][3]` entry with full 10-zone definition: Junk, Trash, Quest, Consume, Div, Value, DE, Equip, Trinket, Ammo
- Copied full category rule table from bags location so items sort identically in bank and inventory

### Aux / TSM price rule functions (`ArkInventoryRules.lua`)
- Added `auxpriceunder(copper)` / `apu(copper)` — true if aux market price ≤ threshold
- Added `auxpriceover(copper)` / `apo(copper)` — true if aux market price ≥ threshold
- Added `tsmpriceunder("source", copper)` / `tpu("source", copper)` — true if named TSM price source ≤ threshold
- Added `tsmpriceover("source", copper)` / `tpo("source", copper)` — true if named TSM price source ≥ threshold
- Added `auxovervendor(percent)` / `aov(percent)` — true if aux market price ≥ vendor sell price × (1 + percent/100)
- Added `deovervendor(copper)` / `dov(copper)` — true if TSM disenchant value exceeds vendor sell price by at least `copper`
- Added `dedbg()` — debug helper rule that prints vendor price, aux market price, and DE value to chat; always returns false
- All functions guard against missing addons (nil checks on `TSMAPI`, `LibStub`, `aux`)

### Suppress item-cache warning on login (`ArkInventoryStorage.lua`)
- `GetItemInfo` returns empty strings for type/subtype during the brief post-login window; suppressed the warning for the `t == "" and s == ""` case — slot is correctly handled as `Slot.Type.Unknown` and re-evaluated on the next scan
