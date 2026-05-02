# Loot Appraiser (3.3.5) — Changelog

## v1.5 — Catch uncategorised items via System "Default" *(2026-05-02)*

The v1.4 vendor-category override only matched items the user had
*manually* dragged into a custom category. ArkInventory's actual
classification chain falls back to System categories (most commonly
SYSTEM_DEFAULT, localised "Default") for everything else — so most of
a typical loot stream still went through LootAppraiser's default
AH/DE/vendor chain instead of being force-vendored.

### Fix
`GetArkInvCategoryName` now returns the string `"default"` when no
explicit assignment exists. Combined with the new default
`arkInvVendorCategory = "Junk,Trash,Default"`, this catches:

* Items the user manually placed in a `Junk` or `Trash` custom
  category → vendor (existing behaviour)
* Items with no manual assignment → reported as `default` →
  matched against the vendor list → vendor

This implements the user's actual workflow:
* Tag valuable items into a `Value` custom category → AH pricing
* Tag DE-able items into a `DE` custom category → disenchant pricing
* Leave everything else alone → force vendor pricing

### Migration (1.4 → 1.5)
Existing installs running the v1.4 default `Junk,Trash` are
auto-migrated to `Junk,Trash,Default`. If you customised the
list (e.g. you added or removed names), the migration leaves
your value alone.

### Caveat
If you don't categorise items at all, every loot row will now
price at vendor regardless of AH potential. To get the old
"AH-by-default" behaviour back, run
`/la vendorcat "Junk,Trash"` (without "Default").

---

## v1.4 — Junk/Trash override, zero-value filter, disenchant fix *(2026-05-02)*

### Junk/Trash vendor override
A third ArkInventory category-name list, default `"Junk,Trash"`. Items
the player has manually placed in any of these categories are forced
to vendor pricing — bypasses any incidental AH listing the item may
have. Configurable via `/la vendorcat <comma-list>`. Empty string
disables the override.

The lookup uses the same `db.profile.option.category["item:<id>:<sb>"]`
→ `db.global.option.category[type].data[code].name` chain as the
existing Value/DE lookups; all three configs now also accept
comma-separated lists (e.g. `/la decat "DE,Disenchant"`).

### Zero-copper rows are dropped
New `skipZeroValueRows` profile setting, default `true`. After pricing
runs, rows whose final per-item value is 0 copper aren't added to the
session — typically vendor-fallback items where the vendor sell price
is also 0 (poor-quality vendor trash, certain quest items, low-tier
crafted reagents). Toggle via `/la skipzero`.

### Disenchant double-counting fix
Two real bugs were causing disenchant to show both the original item
*and* the produced mats in totals:

1. **`Session.ReconcileBags()` was modifying `state.bagOwn` while
   iterating it with `pairs()`** — undefined behaviour in Lua 5.1.
   Depending on hash bucket layout some entries were silently skipped
   per pass, leaving the disenchanted source item in the row list
   while the new mats appeared as fresh rows. Rewrote to collect IDs
   into a local list first, then iterate that list while mutating
   `state.bagOwn`.
2. **Belt-and-suspenders**: also force a reconcile pass on
   `UNIT_SPELLCAST_SUCCEEDED` for `player` casts of Disenchant
   (13262), Milling (51005), or Prospecting (31252). Even with the
   pairs-iteration fix, hooking the spell directly is the most
   robust signal — these are the spells that consume an item and
   produce mats in a single client tick.

---

## v1.3 — Bag reconciliation: deleted/sold/mailed items leave the session *(2026-05-02)*

When loot leaves your bags — destroyed, vendored, mailed, traded — the
session totals and GPH now decrement to match. Previously they only
ever grew, which inflated GPH for any farm where you destroyed greys
along the way.

### Mechanics
- `Session.Start()` snapshots current bag contents into a per-itemID
  baseline. Any loot ingested after that bumps a parallel `bagOwn`
  ledger.
- `BAG_UPDATE` (debounced 0.3s after the last in a burst) triggers
  `Session.ReconcileBags()`. It re-scans bags and, for each tracked
  item where current count is below `baseline + bagOwn`, debits the
  loss — preferring the session ledger first, falling back to the
  baseline only if the entire session-tracked amount of that item is
  already gone.
- `ApplyLossToLootRows()` walks `lootRows` newest-first (LIFO),
  decrementing or removing rows until the loss count is satisfied.
  Per-row value is reduced proportionally for partial losses.

### Why no double-counting against `GoldDelta`
`GoldDelta` (current gold − start gold) and `lootTotal` are independent.
Vendoring an item drops `lootTotal` (item left bags) but raises
`GoldDelta` by the same amount (vendor sale). Net session value
unchanged. Destroying drops `lootTotal` and leaves `GoldDelta` flat —
correct: you really did lose that value. Loot adds to `lootTotal`
without touching `GoldDelta` until you sell.

### Bag scope
Reconciliation scans the regular bags (backpack + 4 bag slots, ids 0
through `NUM_BAG_SLOTS`). Keyring and ammo bag are excluded — they
shouldn't carry tracked loot, and including them caused false
positives on quiver swaps in early prototypes.

---

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
