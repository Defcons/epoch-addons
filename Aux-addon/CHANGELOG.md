# Aux-addon — Changelog

> Originally by shirsig. Heavily modified for Ascension/Epoch by Defcon — version history below is independent from the original addon.

## v1.0 — Ascension/Epoch Modifications

### Bug fix — tooltip crash "Invalid quest item in SetQuestLogItem" (`core/tooltip.lua`)
- Hook wrapper called the original `SetQuestLogItem` (and all other hooked tooltip methods) unconditionally; when `LibExtraTip` called it with a stale/invalid quest item, the WoW API threw before returning
- Fixed by wrapping the original call in `pcall` — on failure the error is caught silently; on success everything proceeds as before

### Bug fix — deposit always showing 1 silver (`tabs/post/core.lua`)
- `unit_vendor_price()` often returns `0` in 3.3.5 when slotting the item; fixed by checking `GetItemInfo(item_id)` return value 11 (vendor sell price) first since it is always reliable once the item is cached; `unit_vendor_price` used only as fallback

### Bug fix — Buyout button never executing the bid
- `PlaceAuctionBid` must be called from a hardware event (button click), not from an `OnUpdate`/scan-thread callback
- Replaced single-click flow with a two-click state machine (`idle → searching → found → idle`) in a `do`-block with private state
- First click: validates selection, starts a list scan to locate the exact auction; state → `searching`, button disabled
- On match found: stores auction index + total price; state → `found`, button re-enabled with "click again to confirm" status
- Second click: IS the hardware event — safely calls `place_bid` and resets state to `idle`
- `reset_buyout_state()` called in `update_item()` to clear stale state when switching items

### Bug fix — Unit Starting Price showing inflated value after auto-selection
- Root cause: `bid_selection` was auto-selected to the cheapest bid row; `undercut()` with `stack=true` produced inflated start prices
- Fix: removed `bid_selection` auto-selection from `update_auction_listing`; `bid_selection` only set when user manually clicks a bid row
- Both start price and buyout price now derive from `buyout_selection`

### Bug fix — price_update running one frame before auto-selections were visible
- `price_update()` was called before `update_auction_listings()` in `on_update()`
- Fix: reordered `on_update()` — `update_auction_listings()` first, then `price_update()`

### New feature — manual price override
- Typing a custom price sets `user_price_override = true`; cleared on item switch or explicit refresh
- `update_auction_listing` skips buyout auto-selection when `user_price_override` is true

### New feature — inventory list auto-scroll to selected item
- Added `M.scroll_to(item_listing, target_record)` to `gui/item_listing.lua`
- Scrolls only when `selected_item` changes; no disruption on same-item refreshes

### Bug fix — Auctions tab selection reset after cancelling an auction
- `CancelAuction()` chain wipes `auction_records` and destroys the selection before rescan completes
- Fix: save `prev_item_key` and `prev_name` before wiping; restore after `update_listing()` with three-tier fallback:
  1. Same `item_key` still has auctions → stay on it
  2. Item is gone → pick next item alphabetically
  3. Nothing after it → fall back to first remaining auction

### New feature — auto-advance to next item after posting
- After clicking Post, selects the first item alphabetically after the one just posted
- Fallback: stay on same item if quantity remains → last item if nothing comes after alphabetically

### New feature — Next button
- New `Next` button in the Post tab toolbar advances to the next item (alphabetical, wraps around)
- Enabled whenever inventory contains at least one auctionable item

### New feature — buyout auto-select lowest price
- After a scan, the first non-historical-value row is automatically selected
- Auto-selection skipped when `user_price_override` is true

### Bug fix — deposit always showing 1s (complete fix)
- Deposit rate corrected to 15%/75% (faction/neutral AH rates)
- Duration dropdown stores enum integers (1/2/3); mapped to actual hours before computing `duration_factor = hours / 12`
- `select(11, GetItemInfo(item_id))` used as primary vendor price source; `GetAuctionSellItemInfo` is unreliable on Epoch

### Bug fix — default stack count now half of total quantity
- Stack count defaults to `floor(total / 2)` (minimum 1) instead of 1
