# Loot Appraiser (3.3.5) — Changelog

## v1.2 — Loot detection: only what actually entered your bags *(2026-05-02)*

Two related bugs:

### Duplicate items from peeking at mob loot tables
`LOOT_OPENED` fires every time a loot window appears, regardless of whether
items are actually taken. Clicking a corpse, glancing at the contents, and
closing the loot frame still counted everything as looted. Re-opening the
same corpse — or another mob with the same drops — counted again.

**Fix:** dropped `LOOT_OPENED`-based ingestion entirely. Loot is now
detected solely from `CHAT_MSG_LOOT`'s `LOOT_ITEM_SELF` /
`LOOT_ITEM_SELF_MULTIPLE` lines, which fire only when an item actually
lands in your bags. Need/Greed roll deliveries also fire those lines —
to keep them excluded, the self-loot patterns are gated on a
"loot window recently open" flag set by `LOOT_OPENED` and cleared
500ms after `LOOT_CLOSED`. Crafted-item lines (`LOOT_ITEM_CREATED_SELF`)
bypass the gate since crafting never opens a loot window.

The recent-seen dedup buffer is gone — with one event source there's
nothing to dedup against.

### Whites/greys still missing despite v1.1 lowering the default
v1.1's `ApplyDefaults` only fills `nil` keys, so installs from v1.0 kept
their saved `minQuality=2` and never picked up the new floor.

**Fix:** added a one-shot migration keyed off `LootAppraiserDB._dbVersion`
that resets `minQuality` and `minQualityForList` to 0 on the v1.2 upgrade.
Future migrations bump `DB_VERSION` and add their own conditional block.

---

## v1.1 — Whites/greys included; ArkInventory category overrides *(2026-04-30)*

- **Default quality threshold lowered to 0** (poor) so greys, whites and
  everything above are tracked. Existing installs keep their saved value;
  use `/la quality 0` to switch.
- **ArkInventory category override** (in `Core/Pricing.lua`):
  - Items manually assigned to a category named **`Value`** (configurable
    via `/la valuecat <name>`) are forced through the AH chain — useful
    for grey/white items that vendor poorly but sell on the AH.
  - Items manually assigned to a category named **`DE`** (configurable
    via `/la decat <name>`) are priced as their disenchant expected
    value via TSM2's enchanting yield tables (mats priced through the
    same Aux/TSM AH chain).
  - Lookup uses ArkInventory's profile cache
    (`db.profile.option.category["item:<id>:<sb>"]`) and walks the
    `db.global.option.category[type].data[code].name` table to read
    the category name. No-op if ArkInventory isn't loaded.
  - Either override falls through to the default chain when the override
    can't produce a price (e.g. AH unknown for a "Value" item; DE not
    applicable to whites/greys).

### Bind-on-pickup detection still applies
The same hidden-tooltip BoP scan determines the soulbound bit used in
ArkInventory's cache key (`item:ID:0` vs `item:ID:1`) so categorisation
matches whatever ArkInventory has in its bag scan.

---

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
