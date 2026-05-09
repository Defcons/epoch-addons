# Loot Appraiser (3.3.5) — Changelog

## v1.15 — Crafted items don't add to session value *(2026-05-04)*

Crafting was visually double-counting: the gathered runecloth showed
as session loot, then the bandage crafted from it showed as additional
session loot. Both now resolve correctly:

### What changed
1. **`LOOT_ITEM_CREATED_SELF*` patterns removed from `LOOT_PATTERNS`.**
   Crafted items aren't real loot — they're transformations of mats
   the player already had. They no longer appear as session rows.
2. **New `CRAFT_PATTERNS` checked separately** in `HandleChatMsgLoot`.
   When a `"You create: …"` line fires, we set
   `craftingWindowUntil = GetTime() + 0.7`.
3. **`ReconcileBags` is skipped during the craft window.** Otherwise
   the BAG_UPDATEs from the spell consuming the mats would debit the
   already-counted gathered runecloth, making session value drop
   whenever the player crafts. The `pendingReconcile` flag still
   resets after each skipped pass so future (post-window) bag changes
   are reconciled normally.

### Net effect
* Loot 12 Runecloth → session shows `Runecloth x12 @ 12g`
* Craft a Heavy Runecloth Bandage (consumes 5 Runecloth + 1 Silk):
  * No new bandage row added.
  * Mats are NOT debited — Runecloth row stays at x12.
  * Session value remains `12g` (the gathered loot).
* Subsequent destroy/vendor/mail outside the craft window still
  reconcile and debit normally.

### Window length
0.7s is enough to cover the typical craft sequence (BAG_UPDATEs +
0.3s reconcile timer + slack) without bleeding much into unrelated
activity. If you destroy or vendor an item within ~0.7s of crafting,
that change won't be debited until the next bag event re-arms the
reconcile.

---

## v1.14 — Vertical resize via bottom-right grip *(2026-05-04)*

The frame can now be resized to show more (or fewer) rows. Drag the
small grip in the bottom-right corner — height grows, width stays
fixed at the button-fit value. This adds rows, doesn't scale.

### Mechanics
- `frame:SetResizable(true)`,
  `SetMinResize(WINDOW_W, MIN_WINDOW_H)` (3 rows),
  `SetMaxResize(WINDOW_W, math.huge)`. Min and max width pinned to
  `WINDOW_W` so width can't drift.
- A standard Blizzard chat-style size grabber (16×16 button textured
  with `Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-*`) lives in the
  bottom-right corner. `OnMouseDown` calls `frame:StartSizing("BOTTOMRIGHT")`,
  `OnMouseUp` calls `StopMovingOrSizing()`.
- `OnSizeChanged` recomputes `MAX_ROWS = floor((h - HEADER - FOOTER) / ROW_H)`
  on every drag tick, lazily builds any new row widgets needed, and
  re-paints. Cheap — `BuildRow` allocates one font string per call
  and is only called for rows that don't already exist.
- On `OnMouseUp` the height is snapped to a clean multiple of
  `ROW_H` so no row is half-clipped, and `windowPos.h` is persisted
  alongside the existing `point/x/y`.
- `RefreshList` now iterates the full `#rows` (not `MAX_ROWS`) and
  hides any row beyond `MAX_ROWS`, so shrinking the frame correctly
  hides the now-out-of-band widgets.

### Restoring a saved larger size
If `windowPos.h` > `DEFAULT_WINDOW_H`, `Build()` applies the saved
height before `OnSizeChanged` is wired up, so the row widgets
wouldn't get created. Worked around by invoking `OnSizeChanged`
once manually at the end of `Build()` — the script's idempotent
"build any rows we don't have yet" logic catches up cleanly.

---

## v1.13 — Single-line header, button-fit width, 8-row scroll *(2026-05-03)*

### Single-line summary header
Two-line v1.12 header collapses to one line:

```
Stratholme · 4:32 · 12g 50s · 1500g/h · 11x
```

The Total field now shows `lootTotal + goldDelta` — the full session
value including gold/silver looted directly from mob corpses (which
arrive as currency via `GetMoney()`, not as item rows). Vendoring an
item raises `goldDelta` while `lootTotal` drops by the same amount
via `Session.ReconcileBags`, so the displayed total stays correct
without double-counting.

### Width fits the 4 buttons exactly
WINDOW_W 290 → 248. Maths:
`6 (left margin) + 56*4 (buttons) + 4*3 (gaps) + 6 (right margin)
 = 248`. No more dead space to the right of the Hide button.

### 8 visible rows with scroll for the rest
MAX_ROWS 14 → 8. Beyond 8, the existing FauxScrollFrame scrollbar
shows up and you can scroll through the full session history (still
capped at `MAX_LOOT_ROWS = 200`). Loot rows now use anchor-to-anchor
layout so the name field expands to whatever space is left after the
value, with `SetWordWrap(false)` for graceful truncation on long
item names.

### Sizing summary
| Dim | v1.12 | v1.13 |
|-----|-------|-------|
| Width  | 290 | 248 |
| Header | 36  | 18  |
| Rows   | 14  |  8  |
| Total  | 226 | 136 |

About **40% smaller** than v1.12 by area.

---

## v1.12 — Compact UI + persistent window position *(2026-05-03)*

### Compact layout
Dropped the big "Loot Appraiser" title and the separate zone subtitle.
Two-line summary header now reads:

```
Stratholme  4:32  190g/h
58g 58s  · 11 items
```

Numbers are colour-coded inline (zone grey, time bright, GPH green,
total bright, item count grey). Pause indicator is a small `*` after
the time instead of the previous `(paused)` parenthetical.

Sizing changes:
* Window width  320 → 290
* Header height  92 →  36 (2 lines + 1px separator)
* Row height     14 →  12
* Footer height  28 →  22 (smaller buttons: 56×18)
* Visible rows   12 →  14 (more density, still capped at
  `MAX_LOOT_ROWS = 200` total)
* Total height  288 → 226 (about 21% smaller)

### Window position remembered between sessions
New profile field `windowPos = { point, x, y }` saved on
`OnDragStop` and restored in `UI.Build()`. Falls back to
`CENTER, 0, 0` when nil (fresh install). `SetClampedToScreen`
keeps it visible after resolution changes even if the saved
coordinates would otherwise land off-screen.

---

## v1.11 — `/la dump` + stack-aware loot patterns *(2026-05-03)*

### Stack support for Ascension wins
The Ascension custom `"You won: …"` chat format wasn't capturing
stack counts. Looting a stack of 5 Runecloth via group greed
ingested as a single Runecloth. Added a stack-aware variant:

```
"^You won: (.+)x(%d+)$"   -- multi
"^You won: (.+)$"         -- single
```

Pattern ordering matters — Lua's engine returns the first match,
so multi must precede single or the count is lost. Same ordering
fix applied to the Blizzard self-loot/self-create patterns
(`LOOT_ITEM_SELF_MULTIPLE` before `LOOT_ITEM_SELF`,
`LOOT_ITEM_CREATED_SELF_MULTIPLE` before its single sibling).

### `/la dump <link>` comprehensive item diagnostic
Replaces v1.8's `/la price` with a much fuller per-item dump grouped
into five sections: Identity, ArkInventory, Config, Pricing, Session.
`/la price` is kept as an alias.

What you get from a single paste:

- **Identity**: link, itemKey (id:suffixID), isBoP, GetItemInfo
  basics (name, quality, ilvl, class/sub, vendor price)
- **ArkInventory**: cache key, raw `<type>!<code>` from
  `db.profile.option.category`, decoded type/code, the global
  category's `.name`, the result of the bag-scan `slot.cat`
  fallback (rule-classified items live there), and what
  `GetArkInvCategoryName` finally returns
- **Config**: the live profile values for `arkInvValueCategory` /
  `arkInvDECategory` / `arkInvVendorCategory` / `useDisenchant` /
  `skipZeroValueRows` / `minQuality*`
- **Pricing**: AH (Aux merged + TSM), DE expected value, vendor
  sell, and the final `(copper, source, isBoP)` decision
- **Session**: zone, total, GPH; up to 5 matching `lootRows`
  with `count`/`unit`/`value`/`src`/`age`; the bag-tracking
  ledger (`baseline` / `bagOwn` / `currentBags`) for the item ID
- **Current bag location**: which bag/slot the item is in right
  now (or "not in bags")

New `Session.GetBagLedger(itemID)` exposes the reconciliation
ledger entries — useful for diagnosing "why didn't this item get
debited when I destroyed it" / "why does it think I have N when
I only have M".

`FormatCopper` helper renders e.g. `61499c (6g 14s 99c)` instead
of just the raw copper number, so values are readable at a
glance.

---

## v1.10 — Ascension custom loot patterns + rule-based categories *(2026-05-03)*

### Catch Need/Greed wins on Ascension's modified server
The verbose trace from `/la verbose` (added in v1.9) caught Ascension
emitting `"You won: [Item]"` on `CHAT_MSG_LOOT` when the player wins
a Need or Greed roll — *not* retail's `LOOT_ITEM_SELF`
("You receive loot: [Item]."). Added a literal Lua pattern to match
the Ascension format. Items received via group rolls now appear in
the session log.

### Rule-classified ArkInventory categories
`GetArkInvCategoryName` previously only consulted
`db.profile.option.category[<key>]` — the explicit-assignment table
ArkInventory writes when the user manually drags an item into a
Custom category. Items classified by an ArkInventory **Rule** (e.g.
"all greens that disenchant" → `DE`) don't write there; the rule
engine instead stamps the resolved category id onto the in-bag
`slot.cat` field during its bag scan.

Added a fallback `GetArkInvCategoryNameFromBags(itemID)` that walks
`ArkInventory.db.realm.player.data[me].location[Bag].bag[*].slot[*]`,
finds the matching slot, and resolves `slot.cat` to a name. The full
lookup chain is now:

1. Explicit assignment (`db.profile.option.category[key]`)
2. **Bag-scan fallback** (`slot.cat` from rules)
3. Last resort: `"default"`

### Re-pricing pass on BAG_UPDATE
Fresh greed-wins have a timing race: `CHAT_MSG_LOOT` fires *before*
ArkInventory has run its bag scan, so on the very first lookup
`slot.cat` is still nil and a rule-classified item resolves as
`default` → vendor. ~300ms later the bag scan completes.

Added `Session.RepriceRecentVendor()` which is called from the same
debounced reconcile tick that handles bag-loss reconciliation. It
walks `lootRows` (newest-first) for at most 5 seconds back, re-
evaluates each row whose source is `VENDOR`, and updates the row
in-place if the new pricing now resolves to AH / DE. Once a row is
promoted off vendor it won't be re-priced again on subsequent ticks
(the `if row.src == VENDOR` guard self-stabilises).

---

## v1.9 — `/la verbose` for loot-pipeline diagnostics *(2026-05-02)*

Added `/la verbose` toggle that prints, for every CHAT_MSG_LOOT:
* the raw message text
* whether `ParseChatLoot` matched (link/count or nil)
* the `IngestLoot` decision tree (quality, ShouldRecord keep flag,
  entry.unit / entry.src, drop reason if dropped, or "ADDED to
  session" on success)

Used to diagnose user-reported "items in Value/Trash custom
categories aren't showing in LA". The trace exposed Ascension's
custom `"You won:"` chat-loot format used for Need/Greed wins,
which v1.10 then catches.

---

## v1.8 — `/la price` debug trace *(2026-05-02)*

Added `/la price <link>` which dumps the full pricing trace for a
single item to chat:

* itemID / itemKey / isBoP
* The exact `item:<id>:<sb>` cache key we look up in
  `ArkInventory.db.profile.option.category`
* The raw `<type>!<code>` value found there (or nil)
* The decoded type/code and the `name` field from
  `db.global.option.category[type].data[code]`
* What `GetArkInvCategoryName` returned (the lower-cased name)
* The active `valueCategory` / `deCategory` / `vendorCategory`
  config strings
* AH price / DE expected value / vendor sell price for the item
* Final `(copper, source, isBoP)` decision

Usage: type `/la price ` then shift-click an item from your bag.
Useful for diagnosing "this item is in my Value/Trash custom
category but doesn't show up" — the trace tells us whether the
cache lookup hit, what name resolved, and which branch fired.

---

## v1.7 — Need/Greed wins are tracked again *(2026-05-02)*

Removed the v1.2 "loot window recently open" gate on `LOOT_ITEM_SELF`.
That gate was meant to keep group-roll deliveries out of the session,
but the side effect was over-aggressive: greed-wins fire
`LOOT_ITEM_SELF` *without* opening a loot window, so items the player
genuinely received via Need/Greed never reached `IngestLoot`.

Net effect of the new flow:

* Solo loot (corpse / chest / mining node) → counted (unchanged)
* Need/Greed win → **counted (regression fix)**
* Master-loot assigned to player → counted
* Crafted item → counted (unchanged, via LOOT_ITEM_CREATED_SELF)
* Other player's Need/Greed win → still ignored — those fire
  LOOT_ITEM, not LOOT_ITEM_SELF, and the LOOT_ITEM patterns are
  intentionally absent from our parser
* Peeking at a mob loot table without taking → still ignored — no
  CHAT_MSG_LOOT delivery line is emitted just for opening the frame

LOOT_OPENED / LOOT_CLOSED event registrations dropped (the gate state
was their only consumer). BAG_UPDATE and UNIT_SPELLCAST_SUCCEEDED
hooks for reconciliation are unchanged.

---

## v1.6 — Consume category routes to AH pricing *(2026-05-02)*

`arkInvValueCategory` default expanded from `"Value"` to
`"Value,Consume"`. Items the user has placed in a `Consume` custom
category (potions, food, reagents, etc) now go through the AH price
chain alongside `Value`. No new code path — the comma-separated list
support already plumbed through `CatNameInList` since v1.4 just plugs
the second name in.

Migration 1.5 → 1.6: existing installs with the previous default
`"Value"` are auto-rewritten to `"Value,Consume"`. Customised values
are left untouched.

---

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
