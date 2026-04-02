# ArkInventory (v1.0)

Originally by Arkayenro. Heavily modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### Ace3 library xpcall fix (Lua 5.1 / 3.3.5 compatibility)
- All embedded Ace3 libraries use the `CreateDispatcher(argCount)` pattern — generates closures via `loadstring` that capture arguments before calling `xpcall(call, errorhandler)` with no extra args
- Fixes the 3.3.5 limitation where `xpcall(f, h, ...)` silently drops variadic arguments
- Affects: AceGUI-3.0, AceAddon-3.0, AceTimer-3.0, AceConfigDialog-3.0, AceBucket-3.0, CallbackHandler-1.0

### Login warning suppressions
- Zero-size bag warning (`WARNING> aborted scan of bag N`) suppressed — caused by a timing race where bags aren't fully initialised before the first scan
- Item cache warning (`WARNING> item cache not updated yet`) suppressed for the brief post-login window — slots are correctly re-evaluated on the next scan

### Bank window zone layout fix
- Bank window now has the same 10-zone layout as regular inventory: Junk, Trash, Quest, Consume, Div, Value, DE, Equip, Trinket, Ammo
- Items sort into the same zones in the bank as in regular bags

### Custom price rules (`ArkInventoryRules.lua`)
- `auxpriceunder(copper)` / `apu(copper)` — true if Aux market price ≤ threshold
- `auxpriceover(copper)` / `apo(copper)` — true if Aux market price ≥ threshold
- `tsmpriceunder("source", copper)` / `tpu` — true if named TSM price source ≤ threshold
- `tsmpriceover("source", copper)` / `tpo` — true if named TSM price source ≥ threshold
- `auxovervendor(percent)` / `aov(percent)` — true if Aux market price ≥ vendor price × (1 + percent/100)
- `deovervendor(copper)` / `dov(copper)` — true if TSM disenchant value > vendor price by at least N copper
- `dedbg()` — debug rule that prints all prices to chat
- All rules nil-guard against missing addons

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Optional: **AuxTSMBridge** for Aux price rules; **TradeSkillMaster** for TSM price rules
