# AuxTSMBridge

A price data bridge between **Aux** auction scanner and **TradeSkillMaster** for **WoW 3.3.5a (Ascension/Epoch)**.

## Features

- Registers two TSM price sources usable in any TSM price string:
  - `AuxMarket` — weighted median across all historical scan data
  - `AuxMinBuyout` — daily low (cheapest buyout seen today)
- Auto-syncs all Aux scanned prices into TSM AuctionDB when the Auction House closes
- Throttled to once per 12 real hours to avoid performance spikes; timer persists across sessions
- Calculates weighted median with exponential time decay (`0.99^days_ago`), replicating Aux's own algorithm
- Parses Aux's raw history strings directly — avoids the `memory allocation error: block too big` that occurs when calling `auxHistory.value()` thousands of times synchronously

## Slash Commands

| Command | Action |
|---|---|
| `/axtsm sync` | Force an immediate sync (resets the 12-hour timer) |
| `/axtsm status` | Print sync status and price source registration info |

## Requirements

- **Aux** auction addon must be installed and have scan data
- **TradeSkillMaster** (v2.x) must be installed

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
