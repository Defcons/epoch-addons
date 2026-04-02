# TradeSkillMaster_AuctionDB — Changelog

> Originally by Sapu94 & Bart39. Heavily modified for Ascension/Epoch by Defcon — version history below is independent from the original addon.

## v1.0 — Ascension/Epoch Modifications

### Bug fixes — data encoding guards
- Added nil and empty-string guards in `decodeScans()` to prevent corruption when day or market value data fails to decode
- Double-validates decoded `day` value before creating scan entries

### Custom data parsing
- Added `DecodeJSON()` function using `gsub()` + `loadstring()` to parse JSON-like app data into Lua tables
- Supports realm/faction data merging with multi-hyphen realm name parsing
- Accepts cross-faction auction data imports within a configurable `MAX_AVG_DAY` time window

### AuxTSMBridge compatibility fix
- Added `or 0` guard on `TSM.data[itemID].quantity` in `GetTooltip()` (line 295) — AuxTSMBridge writes synced items with no auction count; TSM's `encode(0)` stores `"~"` which decodes to `nil`, causing `format("%d auctions", nil)` to crash on item hover
