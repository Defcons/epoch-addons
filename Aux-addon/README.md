# Aux-addon (v1.0)

Originally by shirsig. Heavily modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Changes

### Bug fixes
- **Tooltip crash** (`core/tooltip.lua`) — `SetQuestLogItem` and other hooked tooltip methods now wrapped in `pcall`; stale/invalid quest items no longer crash the tooltip chain
- **Buyout button never executing** — `PlaceAuctionBid` must be called from a hardware event; replaced single-click flow with a two-click state machine (`idle → searching → found → idle`) so the actual bid always comes from a real click
- **Inflated Unit Starting Price** — removed `bid_selection` auto-selection; both start and buyout price now derive from `buyout_selection`, so `unit_start_price ≤ unit_buyout_price` is always satisfied
- **price_update running one frame too early** — reordered `on_update()` so `update_auction_listings()` runs before `price_update()`
- **Auctions tab selection reset after cancelling** — selection is saved before the wipe and restored after rescan with a three-tier fallback (same item → next alphabetically → first remaining)
- **Deposit showing 1 silver** — deposit rate corrected to 15%/75%; duration enum mapped to actual hours; `GetItemInfo` used as primary vendor price source
- **Default stack count now half of total quantity** — stack count defaults to `floor(total / 2)` (minimum 1) instead of 1

### New features
- **Manual price override** — typing a custom price in the start or buyout edit box sets a `user_price_override` flag that prevents auto-selection from overwriting it
- **Inventory list auto-scroll** — after posting or pressing Next, the list automatically scrolls to the newly selected item
- **Auto-advance after posting** — after clicking Post, automatically selects the next item alphabetically
- **Next button** — new toolbar button to advance to the next item in the inventory list (wraps around)
- **Buyout auto-select lowest price** — after a scan, the cheapest real auction row is automatically selected (skipped when `user_price_override` is true)

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Works with **AuxTSMBridge** to share scan data with TradeSkillMaster
