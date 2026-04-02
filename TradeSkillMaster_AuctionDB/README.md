# TradeSkillMaster_AuctionDB (v1.0)

Originally by Sapu94 & Bart39. Heavily modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### Bug fixes — data encoding guards
- Nil and empty-string guards in `decodeScans()` to prevent corruption when day or market value data fails to decode
- Double-validates decoded `day` value before creating scan entries

### Custom data parsing
- Added `DecodeJSON()` function using `gsub()` + `loadstring()` to parse JSON-like app data into Lua tables
- Supports realm/faction data merging with multi-hyphen realm name parsing
- Accepts cross-faction auction data imports within a configurable `MAX_AVG_DAY` time window

### AuxTSMBridge compatibility fix
- Added `or 0` guard on `TSM.data[itemID].quantity` in `GetTooltip()` — AuxTSMBridge writes synced items with no auction count; TSM's `encode(0)` stores `"~"` which decodes to `nil`, causing `format("%d auctions", nil)` to crash on item hover

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Works with **AuxTSMBridge** for Aux price source integration
