# Loot Appraiser (3.3.5) — Changelog

## v1.0 — Initial release *(2026-04-30)*

A live loot tracker with gold-per-hour, AH value, vendor and disenchant pricing.
Inspired by ProfitzTV's *LootAppraiser* (TWW retail), rewritten from scratch for
WoW 3.3.5 + Ascension's unified cross-faction AH.

### Pricing chain (per item)
1. **Aux merged AH price** across every faction scope on the realm
   (mirrors `AuxTSMBridge`'s merge logic; works whether or not the bridge
   has run a TSM sync yet).
2. **TSM `DBMarket`** via `TSM_AuctionDB:GetMarketValue` — fallback when
   Aux has no history for the item.
3. **Disenchant expected value** — for BoP uncommon/rare/epic items when
   the user has DE on. Yields come from TSM2's pre-Cata enchanting
   conversion table (`TSMAPI:GetEnchantingTargetItems` +
   `GetEnchantingConversionNum`); each material is priced through the
   AH chain above so DE values rise and fall with dust/essence/shard markets.
4. **Vendor sell** as the universal floor.

### Loot detection
- Primary: `LOOT_OPENED` walks every loot slot via `GetLootSlotLink` —
  works for autoloot, Quick Loot, manual loot.
- Backup: `CHAT_MSG_LOOT` parses `LOOT_ITEM_*` Blizzard global patterns
  to catch group loot, /roll wins, and crafted-item drops that don't
  open a loot window.
- De-dup buffer: 1.5s window keyed by (link, count, time-bucket) so the
  two paths don't double-count solo loot.

### Session
- One session per game session. Pause / Resume excludes idle time from GPH.
- GPH = `(loot value + gold delta) / elapsed * 3600`. Always >= 1s elapsed
  to dodge divide-by-zero on the first tick.
- Loot rows kept newest-first, capped at `MAX_LOOT_ROWS` (200).

### UI
- Movable frame, Esc-to-hide via `UISpecialFrames`.
- Header: Time / GPH / Total / Items + zone name.
- Body: 12-row scrolling list with per-row colour by quality, source-tag
  suffix (`[ah]` / `[tsm]` / `[de]` / `[v]`), Shift+Click to chat-link,
  Ctrl+Click to dressing-room-preview.
- Footer: Start/Stop / Pause/Resume / Reset / Hide buttons.
- Header ticks every 0.25s; body refresh throttled to 0.1s and only when
  loot is added (or scroll position changes).

### Configuration
SavedVariables in `LootAppraiserDB.profile`:
- `minQuality` — drop-floor for value totals (default: uncommon)
- `minQualityForList` — UI display threshold (default: uncommon)
- `useDisenchant` — substitute DE expected value for BoP items (default: on)
- `showGroupLoot` — track items others loot in your party (default: on)
- `ignoreSoulbound` — exclude all BoP from totals (default: off)
- `autoStart` — auto-start a session on first loot (default: on)
- `showOnLoot` — pop the window on first loot if hidden (default: on)

### Slash commands
`/la` toggles the window. Sub-commands: `start`, `stop`, `pause`, `resume`,
`reset`, `de`, `group`, `soulbound`, `quality <0-7>`, `wipecache`, `help`.

### Cache invalidation
`AUCTION_HOUSE_CLOSED` wipes the in-memory price cache so a fresh Aux scan
flows through immediately. Cache resets per /reload by design (it's all
session-local).

### Notes
- No DE attempt for items at quality below uncommon — TSM's yield table
  doesn't cover them and pre-Cata you can't DE white items.
- Battle pets / heirlooms / legendaries fall through to vendor; they're
  not realistic farm loot on 3.3.5.
- The current session does NOT persist across `/reload`. Each reload
  starts fresh. Cross-reload session resume is on the v1.1 wishlist.
