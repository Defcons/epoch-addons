# Addon Changelog — Ascension (WoW 3.3.5a / Interface 30300)

All addons modified or created with Claude Code assistance for the Ascension private server.

---

## EpogArmory v0.29 — Capture `setBonuses` structured *(2026-04-23)* *(local-only, not released yet)*

The original briefing said to skip set-bonus lines because epoglogs planned a separate `data/item_sets.json` keyed by `setID`. In practice `GetItemInfo` on 3.3.5 doesn't return setID and we have no robust way to key by set, so Darkmantle / Eskhandar / etc. bonus text was being dropped on the floor — the armory tooltip had no set-bonus block at all.

v0.29 captures set bonuses structurally:

```lua
entry.setBonuses = {
    { pieces = 0, text = "Reduces the damage you take from area of effect attacks by 15%." },
    { pieces = 0, text = "Increases the attack speed gained from Slice and Dice by 5%." },
    { pieces = 0, text = "Reduces the Energy cost of your Sinister Strike, Backstab, and Mutilate abilities by 5." },
}
```

**Formats handled** — the parser recognizes three tooltip shapes:

| Tooltip line | `pieces` | `text` |
|---|---|---|
| `"Set: Reduces..."` | `0` (unknown, no prefix) | `"Reduces..."` |
| `"(4) Set: 1% chance..."` | `4` | `"1% chance..."` |
| `"(2/8) Set: ..."` | `2` (the N) | `"..."` |

`pieces = 0` signals "couldn't determine piece count from tooltip" rather than "0 pieces required" — the site should treat 0 as unknown and display the bonus line verbatim. For tooltips that DO include the piece-count prefix, the site can group bonuses by requirement and show them as `Set Bonus (N):`.

**Important caveat on redundancy:** every item in a set carries the SAME set-bonus block in its tooltip. Darkmantle's 8 pieces will each store the same 3 bonus entries. ~200 bytes × 8 pieces = ~1.6 KB duplication per set per user. Site-side can dedup by matching bonus-text sets across items. A future addon release could detect set membership and skip the redundant per-item storage — tracking that as a v0.30+ optimization.

**Schema bump to v6** so v5-cached items re-fetch and pick up the `setBonuses` field. Run `/epogarmory cachewipe && cachebuild` on upgrade.

**Server-side:** epoglogs ingest needs a handler for `setBonuses`. Array of `{pieces, text}` objects; group by `pieces` (treating 0 as "unknown / show verbatim") when rendering the set-bonus block on the armory tooltip.

---

## EpogArmory v0.28 — `tooltipExtras` for proc / use lines *(2026-04-23)* *(local-only, not released yet)*

Items like Eskhandar's Left Claw have special tooltip lines that aren't numeric stats — e.g. `"Chance on hit: Slows enemy's movement by 60% and causes them to bleed for 225 damage over 30 sec."`. These are item flavor / proc descriptions that belong on the armory tooltip but don't fit the `stats` / `tooltipStats` model.

New: `entry.tooltipExtras = { "raw tooltip line 1", "raw tooltip line 2", ... }` — captures lines matching the prefix whitelist `{"Chance on hit:", "Use:"}` verbatim, in order. The site's armory tooltip renders these as-is below the stat block.

Deliberately excludes `"Equip:"` since those are almost always stat lines already covered by `GetItemStats` or the `tooltipStats` pattern list — avoids duplicating the same info in two fields.

The scanner was refactored to do one pass over the tooltip returning both tables (`ScanTooltip(link)` → `stats, extras`). Stats-matched lines are "consumed" and not considered for extras; unmatched lines fall through to the prefix check.

**Schema bump to v5** so v4-cached items re-fetch and pick up the new field. `/epogarmory cachebuild` to force-refresh eagerly, or let scan traffic do it gradually.

Example post-v0.28 cache entry for Eskhandar's Left Claw:

```lua
[18202] = {
    v = 5,
    name = "Eskhandar's Left Claw",
    quality = 4,
    itemLevel = 66,
    icon = "inv_misc_monsterclaw_04",
    stats = {
        ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 48,
        ITEM_MOD_AGILITY_SHORT = 7,
    },
    tooltipExtras = {
        "Chance on hit: Slows enemy's movement by 60% and causes them to bleed for 225 damage over 30 sec.",
    },
}
```

**Server-side:** the epoglogs ingest needs a handler for `tooltipExtras` — treat each array entry as a raw text line and render below the stat block. Additive field; nothing existing breaks.

---

## EpogArmory v0.27 — Ascension PvP percent patterns + set-bonus filter fix *(2026-04-23)* *(local-only, not released yet)*

v0.26 dumpstats turned up two more pattern categories from Rival's gear and Eskhandar's set:

- **Rival's** (Ascension's mid-tier PvP set) uses custom per-player-damage stats — "Increases your damage dealt against other players by 3%" and "Decreases your damage taken from other players by 1%". Not in `GetItemStats` enum; added patterns `DAMAGE_VS_PLAYERS_PCT` / `DAMAGE_REDUCTION_VS_PLAYERS_PCT`.
- **Eskhandar's** set-bonus lines use the `"(N) Set: ..."` format (with piece-count prefix) rather than plain `"Set:"`. The v0.26 filter only caught the plain prefix, so parenthesized variants could potentially match a stat pattern. Tightened the filter to catch `"(N) Set: ..."` and `"(N/M) Set: ..."` as well. No observed false positives in practice but hygienic.

**New patterns (added to the end of `TOOLTIP_STAT_PATTERNS`):**

| Key | Source tooltip pattern |
|---|---|
| `DAMAGE_VS_PLAYERS_PCT` | "damage dealt against other players by N%" |
| `DAMAGE_REDUCTION_VS_PLAYERS_PCT` | "damage taken from other players by N%" |

Values stored as positive integers; sign meaning is implicit in the key name (both are player buffs, regardless of whether the tooltip verb is "Increases" or "Decreases").

**Schema bump to v4** so v3-cached items (v0.26) get re-fetched and pick up the new patterns. Run `/epogarmory cachewipe && cachebuild` to force-refresh on upgrade, or let natural scan traffic do it gradually.

Eskhandar's Left Claw correctly renders with v3 schema, `stats` populated, no `tooltipStats` — the item legitimately has no percent-based tooltip bonuses (only a "Chance on hit" proc, which is an effect not a stat). Confirms the scan path is behaving correctly for items with no matches.

---

## EpogArmory v0.26 — Tooltip-scan for percent-based pre-rating stats *(2026-04-23)* *(local-only, not released yet)*

v0.25 dumpstats confirmed `GetItemStats` genuinely does not return percent-based bonuses on pre-rating-system items — Darkmantle Gloves list `"+1% melee/ranged crit"` as tooltip text but the API's enum has no key for flat-percent crit. These TBC-era set items got grandfathered into WotLK with their original tooltip-only bonuses instead of being converted to rating.

Fix: tooltip-scan items for known percent patterns during `CacheItemInfo` and store matches in a new `entry.tooltipStats` field, separate from the `GetItemStats`-sourced `entry.stats`.

**Patterns captured** (matched from tooltip line text; more-specific patterns win via ordered first-match-break):

*Percent-based (crit / hit / dodge / parry / block / expertise):*

| Key | Source tooltip pattern |
|---|---|
| `CRIT_MELEE_RANGED_PCT` | "critical strike with melee and ranged attacks by N%" |
| `CRIT_SPELL_PCT` | "critical strike with spells by N%" |
| `CRIT_PCT` | "critical strike chance by N%" / "critical strike by N%" |
| `HIT_MELEE_RANGED_PCT` | "hit with melee and ranged attacks by N%" |
| `HIT_SPELL_PCT` | "hit with spells by N%" |
| `HIT_PCT` | "Improves your chance to hit by N%" |
| `EXPERTISE_PCT` | "be dodged or parried by N%" |
| `DODGE_PCT` | "chance to dodge an attack by N%" |
| `PARRY_PCT` | "chance to parry an attack by N%" |
| `BLOCK_PCT` | "chance to block an attack by N%" |

*Flat regen (pre-rating):*

| Key | Source tooltip pattern |
|---|---|
| `MP5` | "Restores N mana per 5 sec" |
| `HP5` | "Restores N health per 5 sec" |

*Flat spell power / healing (TBC-era unified and pre-unified):*

| Key | Source tooltip pattern |
|---|---|
| `SPELL_POWER_FLAT` | "damage and healing done by magical spells [and effects] by up to N" |
| `HEALING_FLAT` | "healing done by magical spells [and effects] by up to N" |
| `SPELL_DAMAGE_FLAT` | "damage done by magical spells [and effects] by up to N" |
| `SPELL_DAMAGE_ARCANE` | "damage done by Arcane spells and effects by up to N" |
| `SPELL_DAMAGE_FIRE` | "damage done by Fire spells and effects by up to N" |
| `SPELL_DAMAGE_FROST` | "damage done by Frost spells and effects by up to N" |
| `SPELL_DAMAGE_NATURE` | "damage done by Nature spells and effects by up to N" |
| `SPELL_DAMAGE_SHADOW` | "damage done by Shadow spells and effects by up to N" |
| `SPELL_DAMAGE_HOLY` | "damage done by Holy spells and effects by up to N" |

*Other pre-rating flats:*

| Key | Source tooltip pattern |
|---|---|
| `DEFENSE_FLAT` | "Increased Defense +N" |
| `SPELL_PENETRATION_FLAT` | "Spell Penetration +N" |
| `BLOCK_VALUE_FLAT` | "Increases the block value of your shield by N" |

Keys deliberately plain uppercase (no `ITEM_MOD_` prefix) to signal they're a separate source from the GetItemStats enum — the site's ingest adds a new handler for them instead of shoehorning into the existing ITEM_MOD_* display map.

**Set-bonus lines skipped** (explicit `^Set:` prefix match), per the original briefing.

**Schema bump to v3** so existing v2 entries (with `stats` but no `tooltipStats`) fall through the cache short-circuit and re-run the full capture pass on next touch. Users can run `/epogarmory cachebuild` once after upgrading to eagerly refresh all stored items; otherwise it happens gradually as new scans come in.

**Server-side work needed:** the epoglogs ingest needs to handle `tooltipStats` alongside `stats` when building the armory tooltip. Separate field, different display logic, additive — nothing existing breaks.

Example post-v0.26 cache entry for Darkmantle Tunic:

```lua
[31180] = {
    v = 3,
    name = "Darkmantle Tunic",
    quality = 3,
    itemLevel = 60,
    icon = "inv_chest_chain_13",
    ts = 1713900000,
    stats = {
        ITEM_MOD_STAMINA_SHORT = 27,
        ITEM_MOD_AGILITY_SHORT = 25,
        RESISTANCE0_NAME = 154,           -- armor
    },
    tooltipStats = {
        CRIT_MELEE_RANGED_PCT = 1,
        HIT_MELEE_RANGED_PCT = 1,
        DODGE_PCT = 1,
    },
}
```

---

## EpogArmory v0.25 — `/epogarmory dumpstats` diagnostic *(2026-04-23)* *(local-only, not released yet)*

User reported that some percent-based stats (expertise, melee crit%, melee hit%) on Ascension items don't seem to land in the captured stats table, and that some stats show up under unusual keys like `RESISTANCE0_NAME`. Need to see actual `GetItemStats` output to know which: missing entirely, present under unrecognized keys, or present with small rating values the site's display map doesn't handle.

Added a diagnostic:

```
/epogarmory dumpstats        — dump all 19 slots
/epogarmory dumpstats 10     — dump a specific slot (hands = 10)
```

For each equipped slot it prints:
- The item name
- Every `GetItemStats` key/value the API returns
- Tooltip lines matching common stat patterns (`%`, `rating`, `increases`, `reduces`, `improves`, `+N...`) for comparison

Run this on an item known to have the missing percent-based stats and compare the `GetItemStats` output vs tooltip lines — tells us whether Ascension serves those stats through the standard enum, custom keys, or purely via tooltip text.

No behavior change to normal addon operation.

---

## EpogArmory v0.24 — Cache-schema versioning (re-fetch stats for pre-v0.22 items) *(2026-04-23)*

(Released publicly as v0.24 on github.com/Defcons/epogarmory-addon/releases/tag/v0.24 — first public release after v0.7.)

Reported from the epoglogs side: items cached before v0.22 (which added `stats`) have `stats_json = NULL` on the server, so their tooltips fall back to TDB — wrong for Ascension-modified items, missing for server-custom items. The addon's `CacheItemInfo` short-circuited on plain presence (`if EpogItemCacheDB[itemID] then return`), so those stale entries never got re-fetched.

Fix: introduce a cache schema version.

- New `CACHE_SCHEMA = 2` constant. `v1 = pre-stats` (name/quality/itemLevel/icon/ts), `v2 = v0.22+ with stats`.
- Every cached entry now carries `entry.v = CACHE_SCHEMA`.
- `CacheItemInfo` early-returns only when `existing.v == CACHE_SCHEMA`; older or missing schema falls through and re-runs `GetItemInfo` + `GetItemStats` to upgrade the entry in place.
- `MarkPendingCache` applies the same check so the retry loop can re-promote stale entries if the initial read blocked on a client-side fetch.

**Migration in practice:** pre-v0.22 entries gradually upgrade as the owning gear shows up in new scans. For an immediate bulk refresh, run `/epogarmory cachebuild` once after upgrading — it now walks every stored player's per-spec gear and any stale entry gets re-fetched. Post-upgrade the short-circuit triggers on matching schema, so there's no perf cost on subsequent scans.

Future schema changes just bump the constant; same mechanism handles the migration.

---

## EpogArmory v0.23 — Fix `ApplySavedPosition`/`SaveFramePosition` upvalue scoping *(2026-04-23)* *(local-only, not released yet)*

Runtime error opening the browser:
```
EpogArmoryUI.lua:706: attempt to call global 'ApplySavedPosition' (a nil value)
```

Same Lua 5.1 upvalue-scoping gotcha as the earlier `RefreshIcons` / `RenderActiveSet` / `BackToBrowser` fixes. v0.20 introduced `SaveFramePosition` and `ApplySavedPosition` as `local function` declarations *after* `BuildBrowser` and `BuildInspectFrame`. The OnShow / OnDragStop closures inside those Build functions reference them — at compile time those names had no matching local in scope yet, so Lua resolved them to globals. At runtime, no global existed → nil → crash on first frame Show.

Fix: forward-declare both at the top of the file (with `RenderActiveSet`, `RefreshIcons`, `BackToBrowser`, `OpenInspectFor`) and change the function definitions from `local function X(...)` to plain `X = function(...) ... end` so they assign to the forward-declared local rather than shadow it.

No behavior change beyond not crashing.

---

## EpogArmory v0.22 — Capture per-item stats via GetItemStats *(2026-04-23)* *(local-only, not released yet)*

The epoglogs armory tooltip already has plumbing for item stats but no data to render. TrinityCore TDB covers stats for retail WotLK items, but Ascension modifies stats on most items, and server-custom items aren't in TDB at all. The only authoritative source is the game client's `GetItemStats(itemLink)` API — which returns the server-supplied stat table with all Ascension changes applied.

This release captures those stats alongside the existing `GetItemInfo` data:

```lua
EpogItemCacheDB[itemID] = {
    name = "Valorous Dreadnaught Faceguard",
    quality = 4,
    itemLevel = 213,
    icon = "inv_helmet_93",
    ts = 1713900000,
    stats = {                                    -- v0.22+
        ITEM_MOD_STRENGTH_SHORT   = 59,
        ITEM_MOD_STAMINA_SHORT    = 88,
        ITEM_MOD_HIT_RATING_SHORT = 18,
        ITEM_MOD_CRIT_RATING_SHORT = 52,
    },
}
```

Keys are exactly what `GetItemStats` returns — the site's ingest translates them to display names via the same enum already used for TDB merging. Net effect: addon-captured stats override TDB stats per-item on the site, so every scanned piece of gear shows correct Ascension values; TDB covers everything that hasn't been mesh-scanned yet.

**Function signature changes:**
- `CacheItemInfo(itemID, itemLink)` — second arg optional; if absent, falls back to a bare `"item:" .. itemID` link (which still returns base item stats)
- `MarkPendingCache(itemID, itemLink)` — stores the link with the pending entry so retries pass it back through
- `TryCachePending` — passes `info.link` back to `CacheItemInfo` on retry
- `CachePayloadItems` — constructs `"item:" .. raw` from each gear slot's full itemstring (preserves enchant/gem/suffix context for the first scan that lands; subsequent scans early-out on the dedup)

**`/epogarmory cachebuild`** also walks per-spec sets (`p.sets[*].gear`) instead of only the legacy `p.gear` mirror, so stats get captured across every stored loadout per player. The dedup makes redundant calls free.

**Wire format unchanged.** Stats are computed locally per receiving client against their own client's item cache. Nothing new crosses the addon-message channel — zero mesh-bandwidth impact.

**File-size impact:**
- Old entry: ~160 bytes
- With stats (4-6 typical): ~350-450 bytes
- 500 cached items: ~200 KB
- 5000 cached items: ~2 MB

Empty `stats = {}` is suppressed for items genuinely without stats (shirts, tabards), so a missing `stats` field reads as "no data captured" rather than "captured but empty".

Random-suffix variants ignored per spec — first roll wins for a given itemID. Fine for raid gear; BoE drops with random rolls might be slightly off but it's a rounding error.

---

## EpogArmory v0.21 — Pre-release polish pass *(2026-04-23)* *(local-only, not released yet)*

Seven small quality-of-life changes to round out the addon before its first public release.

**1. Help text cleanup.** Dropped the `/epogarmory dumpspec` line from the user-visible help (kept the command itself for future Ascension API debugging — just not advertised). Added a `Source + releases: github.com/Defcons/epogarmory-addon` footer line so users know where to report bugs.

**2. Browser auto-refresh.** When `Ingest` stores a new scan, it calls `_G.EpogArmory.OnPlayerChanged(guid)` — the UI registers a no-op-when-hidden callback that calls `browserFrame.Refresh()` if the browser is open. Live updates land without close + reopen.

**3. Empty-state hint.** When `EpogArmoryDB.players` is empty, the browser now shows a centered hint instead of a bare `0 players stored` footer:
> No players stored yet.
>
> Join a group in a dungeon or raid — this client will inspect groupmates and store their gear here. Or type `/epogarmory show <name>` if you've scanned someone already.

Hides automatically as soon as any scan lands.

**4. Per-row scan-age coloring.** Browser rows used to render the age column in flat gray. Now color-coded:
- **Green** if scanned within the last hour
- **Yellow** if today but >1h
- **Gray** if older than 24h

Visual cue for which entries are stale.

**5. Slot-tooltip "Loading..." state.** Hovering a slot whose itemID isn't in the client's cache yet (`GetItemInfo` returns nil) used to render a half-empty tooltip. Now shows `Loading item info...` + `Hover again in a moment.` and kicks off a background `SetHyperlink` fetch via the cache tip. Second hover (~1s later) renders the full tooltip with stats/enchants/gems.

**6. Minimap right-click menu.** Right-clicking the shield icon now opens a `UIDropDownMenu` with: Open Armory · Status · Toggle Debug · Help · Wipe DB · Cancel. Left-click still toggles the browser. Tooltip updated to advertise both interactions.

**7. Updated minimap tooltip** — three lines: left-click action, right-click action, drag note.

---

## EpogArmory v0.20 — Fix Delete + reposition + persistent frame position *(2026-04-23)* *(local-only, not released yet)*

**Delete bug fix.** When I refactored `Ingest` in v0.13 to use the per-spec `sets[tree]` model, I built a fresh `existing` table without copying `entry.guid` onto it. So every player record in `EpogArmoryDB.players[guid]` had `name/realm/class/level/sets/...` but no `guid` field. The Delete button passed `p.guid` (nil) into the popup, the OnAccept handler called `DeletePlayer(nil)`, and the `if not guid then return end` guard short-circuited silently — the entry stayed forever.

Fix:
- `Ingest` now sets `existing.guid = entry.guid` on every store
- `MigratePlayers` backfills `p.guid = guid` for any existing record missing it (runs once on `PLAYER_LOGIN` after upgrade)

**Delete button moved.** Was right of `Back` (cramped header). Now stacked directly below `Back`, same width, so the top-left has a clean `[Back] / [Delete]` column.

**Frame title normalized.** Browser used to read `EpogArmory Browser` and inspect read `EpogArmory`, so the title flickered when swapping. Both now read `EpogArmory` so the swap reads as a single frame's content changing.

**Persistent frame position.** `EpogArmoryDB.config.framePos` stores the last-dragged position (point + relative-point + x/y). Both browser and inspect:
- `OnDragStop` writes the new position to SavedVariables
- `OnShow` applies the stored position before rendering

So drag once, the frame stays there across `/reload` and logout. Both views share one slot since they're meant to look like the same window.

---

## EpogArmory v0.19 — "Made by Defcon" in TOC + per-player Delete button *(2026-04-23)* *(local-only, not released yet)*

**TOC byline.** `Notes` now leads with `"Made by Defcon."` so the credit shows up in the in-game addon list tooltip. Also added `## X-Credits: Made by Defcon` as a custom TOC field for any tool that reads credits separately.

**Delete button.** Inspect frame now has a red-tinted `Delete` button next to `Back` (top-left). Clicking it pops a confirmation ("Delete Defcon from your local armory DB? The mesh will refill this player on the next scan from any peer.") → `Yes` removes the entry and returns to the browser.

What the delete touches:

- `EpogArmoryDB.players[guid]` — the stored gear snapshot, gone from this client
- `EpogArmoryDB.lastScanned[guid]` — the 24h mesh-wide dedup timestamp, cleared so this client can re-inspect immediately when in range
- `seen[guid]` — the 15min per-GUID in-memory inspect cooldown, cleared for the same reason
- If deleting your own player: also clears `lastSelfFingerprint` and calls `RequestSelfScan()` so the next event triggers a fresh self-broadcast (otherwise the fingerprint would still match and the scan would silent-skip)

Exposed via a new `_G.EpogArmory.DeletePlayer(guid)` entrypoint; no public slash command since the button is the intended path.

Consumer semantics: delete is LOCAL — every peer still holds their own copy. Refill depends on someone in the mesh (a) having the target in their DB and (b) rescanning them so they rebroadcast, OR (c) you inspecting the target yourself when they're next in range. No auto-request; it's eventual-consistency.

---

## EpogArmory v0.18 — Shield minimap icon + unified browser/inspect + centerpiece icons *(2026-04-22)* *(local-only, not released yet)*

Three UX changes in one release, plus a small wire-format addition.

**Shield minimap icon.** `MINIMAP_ICON` changed from the stock human-male achievement icon to `INV_Shield_06`. Better signals "armory" at a glance.

**Unified browser + inspect view.** Previously two separate frames (`EpogArmoryBrowserFrame` 320×450 and `EpogArmoryInspectFrame` 290×530) that floated around independently. Now both frames share the same dimensions (320×540) and the navigation helpers `OpenInspectFor(player)` / `BackToBrowser()` copy the on-screen anchor from one to the other on swap, so it reads as a single window with two views.

- Minimap click / `/epogarmory browse` → browser view
- Click a row in browser → inspect view (same position, no jump)
- New **Back** button top-left of the inspect frame → returns to browser view (same position)
- Close button (X) on either → hides everything
- `/epogarmory show <name>` also routes through `OpenInspectFor` so the swap works if browser is already open

Browser row count bumped from 18 → 24 to use the extra vertical space.

**Centerpiece icons in inspect view.** The empty area between the two slot columns now holds:
- **Class icon** (64×64) using the built-in `UI-Classes-Circles` atlas with `CLASS_ICON_TCOORDS` — works for every class without any per-class asset lookup
- **Spec icon** (56×56) using the currently-displayed tree's `iconTexture` from `GetTalentTabInfo` — swaps when you click a different spec button

Wire format addition (v0.7 append-only rule): positions 35/36/37 carry the 3 tab icon texture paths. Old clients (v0.17 and earlier) ignore them; `player.tabIcons` stays nil and the spec icon simply hides until the player is re-scanned.

**Stats summary (#4 in the original request)** deferred to a follow-up. Estimated ~2-3 hours: needs tooltip-scanning each of the 19 slots per viewed player, regex-matching ~20 common stat patterns (`"+52 Stamina"`, `"+39 Strength"`, `"+2% Hit"`, etc.), summing across slots. Enchants and gems come along for free because `SetHyperlink` renders the full enchanted-link tooltip. Moderate work; happy to do it when you want.

---

## EpogArmory v0.17 — Wire tab names so spec labels match server layout *(2026-04-22)* *(local-only, not released yet)*

The v0.14 fix routed gear into `sets[DominantTree(spec)]` correctly, but the UI labels still came from a hardcoded `SPEC_TREE` map in retail WotLK order. Ascension reorders some classes — rogue is `Combat / Assassination / Subtlety`, not retail's `Assassination / Combat / Subtlety` — so a pure-Combat rogue was getting labeled "Assassination 41/20/0" with the Assassination button highlighted.

Dynamic solution: sender reads the 3 tab names from `GetTalentTabInfo(tab, isInspect)` at scan time, appends them at wire positions 32/33/34 (per v0.7 append-only rule). Receiver stores them as `player.tabNames`. UI uses `ResolveTrees(player)` — prefers `player.tabNames` (matches whatever the server actually serves), falls back to `SPEC_TREE[class]`.

**Fixed:**
- `ReadTabNames(unit)` — pulls name strings from `GetTalentTabInfo`; strips `^` and `|` defensively
- Payload positions 32/33/34 now carry tab names
- `entry.tabNames` populated in `ParsePayload` (absent for pre-v0.17 payloads)
- `Ingest` stores `existing.tabNames = entry.tabNames` at player level
- `FormatSpec(trees, spec)` takes the tree array directly instead of looking up by class
- `RenderActiveSet` resolves trees via `ResolveTrees(player)` for both the "Combat 41/20/0" meta line and the button labels
- `SPEC_TREE.ROGUE` updated to Ascension order `{"Combat", "Assassination", "Subtlety"}` so fallback is correct for stale pre-v0.17 entries

Other classes still use retail WotLK order in the hardcoded map — if any turn out to be Ascension-reordered, they'll self-correct on the first v0.17 scan because `player.tabNames` overrides the map.

---

## EpogArmory v0.16 — Fix self `ReadSpecPoints` always returning 0/0/0 *(2026-04-22)* *(local-only, not released yet)*

The bug that's been hiding since v0.3. `ReadSpecPoints` computed the isInspect flag with the idiom:

```lua
local isInspect = UnitIsUnit(unit, "player") and nil or 1
```

For self, that evaluates to `1`, not `nil` — because Lua's `true and nil` is `nil`, and `nil or 1` is `1`. Classic ternary-with-nil gotcha. Every self-scan was calling `GetTalentTabInfo(tab, 1)`, which reads the *inspect* target's data — and you can't `NotifyInspect` yourself, so it returned 0 for every tab. The dumpspec diagnostic in v0.15 proved this: `GTTI(nil)` returned correct points (`41/20/0` for Combat, etc.), but `ReadSpecPoints` returned `0/0/0` on the same line.

Fix: replaced the broken idiom with an explicit `if/then`:

```lua
local isInspect
if not UnitIsUnit(unit, "player") then isInspect = 1 end
```

Self-scans now read real talent points, so `DominantTree` returns the correct tree (1/2/3) and a respec moves the gear into the correct `sets[tree]` slot.

Related: this also explains why "the first test did fetch some talent points" — that first test was probably an *inspect* of another player, which correctly used `isInspect=1`. Self-scans have never worked for talents since they were added in v0.3. The dominant-spec validator added in v0.7 (and removed in v0.8) was rejecting everything for the same reason.

The `/epogarmory dumpspec` diagnostic stays in place — it's useful for future talent-API investigations.

---

## EpogArmory v0.15 — Talent-read diagnostic + simplify GetTalentTabInfo call *(2026-04-22)* *(local-only, not released yet)*

Still landing all scans in `sets[1]` despite v0.14's `DominantTree` keying, which means `ReadSpecPoints` is reading `0/0/0` regardless of actual spec — the explicit `talentGroup` 4th arg I passed in v0.9 is apparently confusing Ascension's classless API.

**Two changes:**

- **Simplified `ReadSpecPoints`** — dropped the explicit `talentGroup` arg from `GetTalentTabInfo` and `GetTalentInfo`. Now uses the 2-arg form (`GetTalentTabInfo(tabIndex, isInspect)`) which defaults to the player's active group per the 3.3.5 API docs. This matches the earliest version of the addon that the user reports *did* successfully read spec points on Ascension.
- **New `/epogarmory dumpspec` diagnostic** — prints every talent-API variant's return for each of the player's 3 tabs, so we can see exactly which call style Ascension actually returns real points-spent for. Also prints `GetActiveTalentGroup()`, `GetNumTalentGroups()`, and the final `ReadSpecPoints` result with the `DominantTree` computation. Run this while on any spec to tell us which API path works.

**Extra debug line** — `[self] scanned self` now includes the spec read: `... spec=51/0/20 tree=1 ...`. Makes it obvious at a glance whether `ReadSpecPoints` is returning real numbers.

---

## EpogArmory v0.14 — Dominant-tree set keying + class-tree button labels *(2026-04-22)* *(local-only, not released yet)*

Fixes the core confusion in v0.13: "3 specs per player" meant the 3 class trees (Assassination/Combat/Subtlety for a rogue), not the dual-spec talent groups. v0.13 was keying sets by `GetActiveTalentGroup()`, which on Ascension's classless system always returns `1`, so every scan landed in `sets[1]` and respecs never triggered a fresh scan — the 24h gate always saw `sets[1]` as fresh.

**What changed:**

- **Set key is now `DominantTree(spec)`** — the index (1, 2, or 3) of the talent tab with the most points. A rogue going 51/0/20 → 0/51/20 moves from `sets[1]` to `sets[2]`, which opens the gate and captures the Combat-spec gear separately.
- **Button labels are class tree names** — `Assassination / Combat / Subtlety` for rogue, `Arms / Fury / Protection` for warrior, etc. Pulled from the existing `SPEC_TREE[classFile]` map in `EpogArmoryUI.lua`. Button width bumped 62 → 90 to fit the longest names ("Assassination", "Beast Mastery").
- **24h self-scan gate removed** — fingerprint check (v0.9) was already catching the `UNIT_INVENTORY_CHANGED` noise silently. The 24h gate on *real* changes was blocking legitimate respec-triggered rescans. Any real fingerprint change now scans. If spam returns from a different angle we'll add targeted throttling then.
- **Wire format (position 31) repurposed** — sender now emits `DominantTree` there instead of `GetActiveTalentGroup`. Receivers ignore position 31 entirely and compute the key locally from `entry.spec` — robust to any sender bug. Position 31 is kept on the wire for forward-compat only.
- **Migration** — runs once on `PLAYER_LOGIN` and handles both pre-v0.13 flat entries (wrap into `sets[DominantTree(spec)]`) and v0.13 sets keyed by `activeTalentGroup` (re-key each entry by `DominantTree(set.spec)`; if two collide on the same new key, newest-scanTime wins). Logs `[migrate] normalized N player entries to DominantTree keys`.

**UI trivia:** the meta-text "Spec N · Scanned…" line dropped the "Spec N" prefix since the currently-active button already shows the tree name.

---

## EpogArmory v0.13 — Per-spec gear sets + expanded filters + 24h self-scan *(2026-04-22)* *(local-only, not released yet)*

Big feature release. Four things.

### 1. Per-spec gear storage (3 sets per player)

The DB shape was one gear snapshot per player GUID. Now it's one per active talent group — up to 3 sets per player (group 1 / 2 / 3). Respeccing or dual-spec-switching captures the new spec's gear without overwriting the old spec's set.

**Data model change:**
```
-- Before
players[guid] = { name, realm, class, level, spec, gear, scanTime, zone, scannedBy }
-- After
players[guid] = {
    name, realm, class, level,
    sets = {
        [1] = { spec = {s1,s2,s3}, gear = {...}, scanTime, zone, scannedBy },
        [2] = { ... },
        [3] = { ... },
    },
    spec, gear, scanTime, zone, scannedBy,  -- mirror of the latest set (UI compat)
}
```

**Migration:** on `PLAYER_LOGIN`, every pre-v0.13 flat entry is wrapped into `sets[1]` (with a `[migrate] wrapped N pre-v0.13 players into sets[1]` debug line). The top-level mirror stays populated to latest set on every Ingest, so the browser and any old consumers keep working unchanged.

**Wire format:** `activeTalentGroup` appended at payload position 31, per the v0.7 append-only rule. Old v0.12 clients ignore it. v0.13 clients default to `1` when the field is absent. No PROTO bump — mesh is forward-compatible.

### 2. Spec switcher in the inspect window

Three buttons (`Spec 1`, `Spec 2`, `Spec 3`) between the meta header and the gear grid. Opening a player defaults to whichever group has the most recent scan. Click a button to swap the displayed set. Empty groups (no scan yet) show the button dimmed + disabled. Inspect frame extended 30px vertically to fit the button row without cramping the slots.

### 3. Expanded "invalid loadout" filter

Both sender (`BuildPayload`) and receiver (`ShouldStore`) now reject scans where:

- **Name match, any slot** — `"Rugged Sandle"` or `"Rugged Sandal"` (resolved via `GetItemInfo`, so it works across any Ascension-custom item ID that has this name).
- **Name match, trinket slots only (13, 14)** — any item with `"Insignia"` in the name. Covers PvP insignia trinkets.
- **Enchant tooltip scan, boots (slot 8) + gloves (slot 10) only** — any enchant line containing `"Mithril Spurs"`. Sender-side only (tooltip-scanning is cheap locally but expensive to re-do on every received broadcast; we trust mesh peers running the same filter).
- **Pre-existing** — `"Enchant Gloves - Riding Skill"` enchant ID (464) continues to catch the Minor Mount Speed glove enchant by ID fast-path.

### 4. Self-scan: per-spec 24h rate limit

`TryScanSelf` now skips the scan when the *currently-active talent group*'s set is less than 24h old, even if gear changed. Respeccing to a different group is not blocked — the new group's set has its own (stale or absent) scanTime, so the gate opens immediately after a spec switch. The fingerprint check (v0.9) is still the silent fast-path for "nothing changed at all"; the 24h gate is the rate-limit for "something changed but we scanned this spec recently".

Log lines:
- `[self] skip — spec 1 set scanned 3.4h ago (24h rate limit)` — the 24h gate holding a gear-change broadcast
- (silent) — fingerprint unchanged, no log noise every 15s

---

## EpogArmory v0.12 — Slow down peer broadcast chatter *(2026-04-22)* *(local-only, not released yet)*

`BROADCAST_STAGGER` was `0.3s` — each scan drained its 6 addon-messages (3 chunks × 2 channels) in ~1.8s, pushing ~290 B/s of outgoing chatter for the user's client and their mesh peers.

There's no reason peer clients need scan data within seconds — the payoff is "you can inspect them from the armory sometime today", not "within 2 seconds". And at 290 B/s you can get uncomfortably close to Blizzard's ~800 B/s addon-message throttle during raid-roster churn, where bursting 30+ fresh inspects in the first minute of a raid briefly pushes the queue full-tilt.

Bumped to `2.0s`:
- Each scan drains over ~12s (still well under a bathroom break)
- Outgoing ~45 B/s — trickle, never near the throttle
- Local `[inspect]` → `[store] OK` direct-ingest stays instant, so your own storage is immediate
- Inspect pacing (`INSPECT_INTERVAL = 2.5s`) unchanged, so the scan throughput isn't the bottleneck
- Burst of 40 fresh inspects now drains in ~8 minutes instead of ~72s, which is fine — raids last hours

---

## EpogArmory v0.11 — Drop self-echoes in `OnAddonMessage` *(2026-04-22)* *(local-only, not released yet)*

Every broadcast we sent was echoing back to our own client — once per channel — and being processed as if it were a real peer scan. The debug log was showing 2x `[recv] new scan from <self>` + 2x `[store] SKIP` per scan, and duplicate `[version] <self> is on vX` pings at T+120s because the ping also hit both PARTY+GUILD. None of it is useful (our own scans and pings are already direct-handled locally before broadcast).

Fix: one line at the top of `OnAddonMessage` drops addon-messages where `sender == UnitName("player")`. Clean exit — no reassembly, no store attempt, no log. Own broadcasts still reach other players normally; they just don't round-trip through our own receive path.

Expected before:

```
[send] Borna: 3 chunks x 2 channels [PARTY+GUILD]
[store] OK: Borna (direct ingest)
[recv] new scan from Defcon (chunk 1/3...)        ← echo 1
[recv] complete
[store] SKIP: existing snapshot is newer
[recv] new scan from Defcon (chunk 1/3...)        ← echo 2
[recv] complete
[store] SKIP: existing snapshot is newer
```

After:

```
[send] Borna: 3 chunks x 2 channels [PARTY+GUILD]
[store] OK: Borna (direct ingest)
```

---

## EpogArmory v0.10 — Fix `/epogarmory wipe` not re-scanning self *(2026-04-22)* *(local-only, not released yet)*

After `/epogarmory wipe`, the next self-scan would short-circuit because the in-memory `lastSelfFingerprint` (added in v0.9) still held the pre-wipe value — fingerprint matched the current state, so `TryScanSelf` skipped with `[self] skip — unchanged`, and the wiped DB never got the user's own player re-added unless they swapped gear or `/reload`ed.

Fix: the wipe command now also clears `lastSelfFingerprint` and proactively calls `RequestSelfScan()`, so a fresh scan fires within the 2s debounce window. Chat message updated to reflect this: `"wiped players + lastScanned (kept config) — self-scan queued"`.

---

## EpogArmory v0.9 — Robust talent read + self-scan dedup *(2026-04-22)*

Two fixes: restore working talent reads on Ascension (v0.8 dropped the gate, but we actually want the data), and stop spamming duplicate self-broadcasts every ~15s.

**Self-scan dedup (new).** `UNIT_INVENTORY_CHANGED` fires on the player every ~15s on Ascension for reasons unrelated to real gear swaps (durability ticks, aura procs, server-side inventory refreshes). Without a dedup gate, every fire triggered a fresh broadcast of the same 532-byte payload — spamming GUILD chat, spamming every other mesh client, and spamming the local debug output:

```
[self] scanned self — 19 slots equipped, payload 532 bytes
[send] Defcon: 3 chunks x 1 channels [GUILD]
[recv] new scan from Defcon (own broadcast echoing back through guild)
[store] SKIP: existing snapshot is newer (15:58:01 vs 15:58:01)
```

Note: the 24h `HasFreshScan` dedup only gates *other-player inspects* via `AddUnit()`. Self-scans have always been a separate path. The new fix fingerprints `level + talents + gear itemStrings` at the top of `TryScanSelf`; if nothing meaningful has changed since the last broadcast, the scan short-circuits with `[self] skip — level/talents/gear unchanged since last scan`. Real gear swaps and respecs still go through immediately.

**Robust talent read.** Earlier versions of this addon successfully fetched talent points on Ascension, so v0.8's "just drop the spec gate" was the right immediate fix but the wrong long-term one — we want the data so we can build per-spec gear sets later. This release makes the talent read robust.

**New `ReadSpecPoints(unit)` helper** in `BuildPayload`:
1. First tries `GetTalentTabInfo(tab, isInspect, nil, activeGroup)` with an explicit `activeGroup` from `GetActiveTalentGroup()` — Ascension's classless system doesn't always default to the active group correctly.
2. If that returns 0 for a tab, falls back to iterating `GetTalentInfo(tab, i, ...)` across every talent in the tab and summing `pointsSpent` directly. This bypasses whatever is breaking the tab-level aggregation.
3. Returns 0 only when both paths report zero — a real "no points spent" result.

**New event: `PLAYER_TALENT_UPDATE`** → triggers a self-scan. Respecs, dual-spec switches, and Ascension talent-tree changes now capture fresh talent data instead of waiting for the next gear change.

**Forward-looking note:** `GetActiveTalentGroup()` is captured inside `ReadSpecPoints` but isn't yet broadcast on the wire. When we add per-spec gear storage in a later release, the plan is to append `activeGroup` as position-31 in the payload (per the v0.7 append-only rule), so v0.9 clients can keep ingesting without a protocol bump.

---

## EpogArmory v0.8 — Drop dominant-spec gate (broken on Ascension classless) *(2026-04-22)*

The v0.7 dominant-spec validation rejected every scan — including fully-geared L60 self-scans — because Ascension is classless and `GetTalentTabInfo(tab, ...)` returns 0 points-spent for every tab regardless of the player's actual talent investment. Observed in-game:

```
[self] scanned self — 19 slots equipped, payload 532 bytes
[store] REJECT: Defcon L60 — no dominant spec (0/0/0)
```

Fix: removed the dominant-spec check from `ShouldStore()` along with the `MIN_STORE_DOMINANT` / `MIN_STORE_TOTAL` constants. The addon now gates on level + gear-equipped count only; the server-side validator in `warcraftlogs-epog routes/admin.js` keeps the final say on what gets published to the public armory. Spec fields in the payload stay (wire format unchanged) — they're just not used for gating.

---

## EpogArmory v0.7 — Version ping + mesh forward-compat *(2026-04-22)*

Peer-to-peer new-release notification plus a lenient mesh parser so additive wire-format changes no longer fragment older clients.

**Version ping (`VER^<version>`):**
- One-shot broadcast at `T+120s` after login on GUILD/PARTY/RAID (whichever channels are available). Deferred 60s at a time if no channel exists yet.
- Receivers compare against their own `## Version` via `GetAddOnMetadata`. If the sender is newer, a single chat line prints: *"EpogArmory: newer version vX.Y available (you're on v…). Download: https://github.com/Defcons/epogarmory-addon/releases/"* — guarded by a session flag so it only fires once.
- Reuses the existing chunked-message framing (msgID^idx^total^body). VER pings are always 1 chunk; `OnAddonMessage` routes by payload prefix (`VER^` → `HandleVersionPing`, else `Ingest`).
- `CompareVersions()` does numeric-tuple semver compare — ignores non-digit suffixes.

**Mesh forward-compat:**
- Parser gate softened from `t[1] ~= "v1"` to accept `"v<PROTO>"` or `"v<PROTO>.<minor>"`. Reserves `"v2"` for a real breaking change.
- Documented append-only rule: new fields must go *after* gear slot 19 (position 31+). Old clients read exactly `t[1]..t[30]` and silently drop anything beyond, so future additions (e.g. ilvl, glyphs, enchant hashes) ride the same PROTO without fragmenting the mesh.

**Addon-message prefix renamed `"EpArmr"` → `"EpogArmory"`.** No deployed users yet, so this is a free rename — brings the wire prefix in line with the addon name.

**Also in this release (previously uncommitted when the session started):**
- Dominant-spec validation in `ShouldStore()` — scans are only accepted when `max(spec) ≥ 31` OR `sum(spec) ≥ 61`, mirroring `warcraftlogs-epog routes/admin.js computePrimaryTree()`. Freshly-dinged 0/0/0 players are now skipped. Hybrid Ascension builds like 25/23/23 still resolve because `sum ≥ 61` covers the 71-points-at-L60 case.
- TOC `Author: Defcon`.

---

## EpogArmory v0.6 — Rename EpochArmory → EpogArmory (brand consistency with epoglogs.com) *(2026-04-22)*

Full rename across the project and sibling web repos for branding consistency with epoglogs.com:

- Addon folder `EpochArmory/` → `EpogArmory/`
- Lua files: `EpochArmory.lua` / `.toc` / `EpochArmoryUI.lua` → `EpogArmory.lua` / `.toc` / `EpogArmoryUI.lua`
- SavedVariables: `EpochArmoryDB` → `EpogArmoryDB`, `EpochItemCacheDB` → `EpogItemCacheDB`
- Slash commands: `/epocharmory …` → `/epogarmory …`
- Chat prefix in all print output: `|cffffaa44EpochArmory|r` → `|cffffaa44EpogArmory|r`
- Frame names (`EpochArmoryInspectFrame`, `EpochArmoryBrowserFrame`, `EpochArmoryMinimapButton`, etc.) renamed accordingly
- `EpochArmoryDebug` global → `EpogArmoryDebug`

**Sibling project renames** (for completeness — tracked in their own repos):
- `C:\Dev\epoch-data` → `C:\Dev\epog-data`
- `C:\Dev\epocharmory-web` → `C:\Dev\epogarmory-web`
- `C:\Dev\warcraftlogs-epoch` → `C:\Dev\warcraftlogs-epog` (actually existed already as the canonical project; the typo folder was deleted)

**Wire-protocol PREFIX unchanged** — still `"EpArmr"` (16-char addon-message channel identifier; changing would fragment the mesh across any older client versions).

**SavedVariables migration:** ⚠️ existing users will lose their scanned data on upgrade — the SV filename changes from `EpochArmory.lua` to `EpogArmory.lua`, and the variable names change from `EpochArmoryDB` to `EpogArmoryDB`. Since the user testing had ~4 players, re-scanning is simpler than writing migration code. If you want to preserve data, copy `WTF/Account/<ACCT>/SavedVariables/EpochArmory.lua` to `EpogArmory.lua` AND edit it to rename the two variables before running the new addon.

**Preserved (legitimately named "Epoch"):**
- Game install path `epoch_live/`
- In-game asset filenames like `inv_misc_coin_epoch_titan` (Ascension's own server content)
- In-game spell titles like "Title: Of Epoch"
- Historical CHANGELOG entries for v0.1..v0.5 (they describe what happened under the old name)

---

## EpochArmory v0.5 — Item-info cache (GetItemInfo → SavedVariable) *(2026-04-22)*

New `EpochItemCacheDB` SavedVariable that persists `GetItemInfo()` results for every itemID seen in any scan (local or received via mesh gossip). Populated with:

```lua
EpochItemCacheDB[itemID] = { name, quality, itemLevel, icon, ts }
```

This closes the last data gap — Ascension's custom items aren't in Wowhead or TrinityCore, but `GetItemInfo()` returns real server-authoritative data for anything the client has seen. Between all mesh participants, the cache converges to full coverage of every item anyone has scanned.

**Implementation:**
- `CacheItemInfo(itemID)` — queries `GetItemInfo`, persists result. Triggers a hidden-tooltip `SetHyperlink` when uncached to ask the server for the data.
- `pendingCache` in-memory queue with OnUpdate retry loop (`CACHE_RETRY_INTERVAL = 0.5s`, gives up after 15s if the server never responds).
- Hooked into `Ingest()` so every scan (local or received gossip, accepted or rejected) feeds the cache with `CachePayloadItems(entry)`.
- `/epocharmory cache` — show cache size + pending count.
- `/epocharmory cachebuild` — iterate all stored players, seed the cache from their gear itemIDs. Useful after first install (fills cache from existing DB without waiting for new scans).
- `/epocharmory cachewipe` — reset the cache (persistent + pending).
- Status line shows `cache=N cachePending=M`.

**Upload flow:** the same `EpochArmory.lua` SavedVariables file now contains both `EpochArmoryDB` (player data) and `EpochItemCacheDB` (item lookup). epocharmory-web parses both and merges the cache on top of its DBC-derived `items.json` at upload time — no separate file, no extra step.

---

## EpochArmory v0.4 — Fixed slot borders + minimap button + browser frame *(2026-04-22)*

- **Slot button redesign:** each slot now uses the Blizzard paperdoll empty-slot texture (`Interface\PaperDoll\UI-PaperDoll-Slot-<Head|Neck|...>`) as a dim background so users can see which slot is which even when empty. Replaced the glowy offset `UI-ActionButton-Border` with 4 thin vertex-colored rectangles (via the white `ChatFrameBackground` texture) that frame the slot exactly. Quality colors (green/blue/purple/orange) now sit flush against the icon instead of bleeding past it.
- **Minimap button:** added `EpochArmoryMinimapButton`. Click → toggles the browser. Drag around the minimap edge → persisted in `EpochArmoryDB.config.minimapAngle` so the position survives reloads. Created lazily on `PLAYER_LOGIN` so the saved angle is available.
- **Browser frame:** new searchable list at `/epocharmory browse`. `FauxScrollFrameTemplate` with 18 visible rows. Top EditBox filters by substring match on player name. Rows show class-colored name + level + class + "N h ago" scan age. Click row → opens the paperdoll inspect frame for that player. Footer shows `X of Y match` or `N players stored` when unfiltered. Escape closes (added to `UISpecialFrames`).
- **Inspect frame:** slots are now 40×40 (was 37×37) to match the new background textures cleanly.
- Slash: `/epocharmory browse | browser | search` (all aliases) opens the browser.

---

## EpochArmory v0.3 — Self-scan + chat prefix rename + short retry on transient fails *(2026-04-22)*

- **Self-scan:** client now scans its own gear and stores it in `EpochArmoryDB` without needing a NotifyInspect roundtrip. `GetInventoryItemLink("player", slot)` works directly. Triggered by `UNIT_INVENTORY_CHANGED` (debounced 2s so equipping a 19-slot set doesn't fire 19 times) and once on `PLAYER_LOGIN` after a 3s warmup for talent data. Respects the same `requireInstance` + out-of-combat gates as other scans. Also broadcast-published so mesh participants get your updated loadout.
- **Talent-read fix:** `BuildPayload` now passes `isInspect = nil` for self (no NotifyInspect in flight), `isInspect = 1` for others. Before, self-scan would've read stale or no talent data.
- **Chat prefix rename:** display prefix in all chat output is now `|cffffaa44EpochArmory|r` (was `EpArmr`). Addon-message `PREFIX = "EpArmr"` constant unchanged — that's the wire protocol, not user-facing.
- **Transient-failure retry shortened:** `[inspect] DROP` (BuildPayload returned nil — usually "0 slots equipped" when the server's inspect response was incomplete) and `[inspect] TIMEOUT` now mark the GUID with a 30s retry (`OUT_OF_RANGE_COOLDOWN`) instead of the 15-min post-successful-scan cooldown (`INSPECT_COOLDOWN`). Target gets another shot on the next roster tick.

---

## EpochArmory v0.2 — Paperdoll inspect frame from DB *(2026-04-22)*
New `EpochArmoryUI.lua` adds an in-game paperdoll frame that renders the latest stored snapshot for any player by name, served directly from `EpochArmoryDB`.

- **Slash:** `/epocharmory show <name>` — or `/epocharmory show` with a player targeted
- **Layout:** 2-column paperdoll (8 slots per column + 3 weapons at bottom), draggable, Escape closes (added to `UISpecialFrames`)
- **Header:** class-colored name, level, class, detected talent tree (tab with most points) + point distribution `Arms 54/17/0`, scan age (`14h ago [raid]`), scanner who captured it
- **Slot buttons:** rendered via `GetItemInfo(itemID)` for icon + quality border. Empty → dim slot with "(empty)" tooltip. On hover → full `GameTooltip:SetHyperlink(...)` tooltip (enchants/gems included via itemString). Click → insert item link into open chat edit
- **Uncached items:** 3.3.5 has no `GET_ITEM_INFO_RECEIVED` event, so when `GetItemInfo` returns nil we force a background fetch via a hidden `GameTooltip:SetHyperlink()` and re-poll at 0.3s intervals for up to 4s, updating icons as they resolve
- **Slash hook:** UI file wraps the existing `SlashCmdList["EPOCHARMORY"]` handler so all prior commands still work

TOC now loads `EpochArmory.lua` then `EpochArmoryUI.lua` (order matters — UI hook reads the existing slash handler).

---

## EpochArmory v0.1 — NEW (consolidated from Scanner + Collector) *(2026-04-21)*
Unified into one addon. Every client does everything: scans groupmates in dungeons/raids, broadcasts chunked gear via `EpArmr` addon prefix, receives + reassembles other clients' broadcasts, stores latest snapshot per GUID. Every participant's `EpochArmoryDB` is a valid upload source.

**Why consolidated:** the original split (lightweight scanner + heavyweight collector) was designed to spare "scanners" from storing the DB. In practice the DB is tiny (~1-2MB for thousands of players) so the split only added code duplication and an awkward ACK-less mesh where only Collectors captured data. Making every client both sender and receiver eliminates the "is a collector online?" question, removes the need for a persist-until-delivered ACK protocol, and means any participant can export for upload.

**Features carried over:**
- Pipe-separated payload `v1^name^realm^class^level^guid^spec^ts^zone^slot1..19` with itemString colons preserved (enchants + gems captured via slot fields 2-6)
- Chunked at 200 bytes, staggered 0.3s sends, reassembly keyed by `sender\001msgID`, 60s GC for partials
- Inspects only in dungeon/raid by default (configurable via `/epocharmory instance off`), out of combat, targets ≥ L60, ≥10 equipped slots
- `UTILITY_ITEMS` + `UTILITY_ENCHANTS` filter (Carrot on a Stick, Riding Crop, fishing poles, Chef's Hat, mount-speed glove enchant) — rejection preserves older real-gear snapshot
- 24h persistent scan cooldown via `EpochArmoryDB.lastScanned[guid]`, updated on both local inspects AND received broadcasts — mesh-wide cooldown sharing
- `EpochArmoryDB.players[guid]` keyed by GUID, latest `scanTime` wins
- Tagged debug output: `[roster]`, `[inspect]`, `[send]`, `[recv]`, `[asm]`, `[store]`
- Slash: `/epocharmory status | debug | list | wipe | instance on|off`
- SavedVariable: `EpochArmoryDB = { meta, config, players, lastScanned }`

**Removed:** `EpochArmoryScanner/` and `EpochArmoryCollector/` folders (see commits `ac02382`..`741e360` for the split-era history).

---

## (archived) EpochArmoryScanner v1.0 + EpochArmoryCollector v1.0 — split architecture *(2026-04-21, superseded same day)*
Armory data pipeline for epochlogs.com. Two paired addons sharing the `EpArmr` addon-message prefix.

**EpochArmoryScanner** (distributed widely):
- Inspects group/raid members on `PARTY_MEMBERS_CHANGED` / `RAID_ROSTER_UPDATE` / 10s roster tick
- One `NotifyInspect` at a time, 4s timeout, 2.5s spacing, 15min rescan cooldown per GUID
- Builds pipe-separated payload: `v1^name^realm^class^level^guid^spec1^spec2^spec3^ts^zone^slot1..slot19` where each slot is the raw `itemString` (colon-separated) stripped from the itemLink
- Chunks to 200-byte bodies (under 255-byte addon-msg cap), staggers sends 0.3s apart
- Broadcasts to RAID/PARTY + GUILD (fan-out so guild collectors catch in-party scans)
- **Instance-only scanning configurable** — default on, toggle via `/epocharmoryscanner instance off` / `/epocharmorycollector instance off` for testing. Persisted in SavedVariables (`EpochArmoryScannerDB.requireInstance`, `EpochArmoryDB.config.requireInstance`). When on, scans are skipped outside 5-man/raid instances
- **Out-of-range retry** — targets that fail `CanInspect()` (too far away / not visible) get a 30s cooldown instead of the full 15-min cooldown, so they re-enter the queue as soon as you're close enough
- **24h persistent scan cooldown** — `SCAN_FRESH_WINDOW = 86400`. Scanner checks `EpochArmoryScannerDB.lastScanned[guid]` (written on every successful scan) and Collector checks `EpochArmoryDB.players[guid].scanTime` — both skip `AddUnit` entirely if we already have fresh data, so a player scanned in yesterday's raid won't be re-scanned in today's. Survives `/reload`.
- **Scanner gossip mesh** — Scanners now also register `CHAT_MSG_ADDON`, reassemble other scanners' broadcasts, and update `EpochArmoryScannerDB.lastScanned[guid] = payload.scanTime` when a fresher timestamp arrives. Scanners don't store gear (only the Collector does) — they only learn "this GUID was scanned at time T" so they won't waste their own inspect cycles. Within a guild/raid, Scanner A's broadcast suppresses re-scans across every other Scanner in range for 24h. `[gossip] learned X scanned at HH:MM by Sender` debug line shows when the mesh saves an inspect.
- **Descriptive debug output** — every scan/broadcast/receive/store decision now prints a tagged line (`[roster]`, `[inspect]`, `[send]`, `[recv]`, `[asm]`, `[store]`) with the reason on skips/drops/rejects, so you can tell why a particular target wasn't captured
- **Scanner waits until player is out of combat** (`InCombatLockdown()`) — queue still builds during fights, drains between pulls
- Skips targets <L60, skips naked/<10-equipped scans at source
- Enchants + gems preserved — itemString is `itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel`
- Self-disables if `EpochArmoryCollector` is loaded (collector does everything)
- Slash: `/epocharmoryscanner status | debug | instance on|off`

**EpochArmoryCollector** (only the armory curator installs):
- Full scanner half (same logic, duplicated — scanner file notes this)
- `CHAT_MSG_ADDON` listener reassembles chunks keyed by `sender\001msgID`, 60s GC for partials
- `Ingest()` parses payload, rejects: `level < 60`, zone not in {party,raid}, `equipped < 10`, or any slot matching `UTILITY_ITEMS` (Carrot on a Stick, Riding Crop, fishing poles, Chef's Hat, etc.) or `UTILITY_ENCHANTS` (mount-speed glove enchant)
- Rejection does NOT overwrite existing entries — a "utility loadout" scan leaves the older real-gear snapshot intact
- Dedup by `GUID`, latest `scanTime` wins (older snapshots discarded)
- Direct-ingests own scans locally (works even with no group to echo back)
- Stores to `EpochArmoryDB.players[guid] = {name,realm,class,level,spec,scanTime,zone,gear,scannedBy}`
- Slash: `/epocharmorycollector status | list | debug | wipe | instance on|off`

**Protocol notes for future changes:** bump `PROTO = "1"` constant in both files if the payload schema changes — collector drops mismatched versions.

**Known limits:**
- Addon messages reach only PARTY/RAID/GUILD — cross-realm/BG unreachable (3.3.5 constraint)
- `MIN_STORE_LEVEL` = 60 (both inspect-side and store-side)
- PvP gear detection deferred to webpage via itemID blacklist (addon can't detect from itemString alone)

---

## Aux-addon v1.3 — Back button + Escape *(2026-04-06)*
- **Back button** in bottom toolbar returns to the previously selected tab
- **Mouse Button4** (back side button) triggers Back from anywhere in the Aux frame, even while hovering item rows (uses `IsMouseButtonDown` polling — child frames don't bubble mouse events on 3.3.5)
- **Search-tab aware:** on the Search tab, Back returns to the previous subtab (e.g. Results → Saved Searches) before falling back to top-level tab history
- **Escape closes Aux:** hooks `CloseSpecialWindows` so Escape always hides AuxFrame
- **Nil guards in post settings:** fixed `read_settings()` returning nil reference instead of calling `get_default_settings()`; guarded `nil` `start_price`/`buyout_price` in price getters and `update_item()`

---

## DeleteItems v1.1 — Escape support *(2026-04-06)*
- **Escape closes the window:** main and junk-scanner frames registered with `UISpecialFrames`. Open confirmation popups close first, then the main window

---

## PlateBuffs v1.1 — Nameplate↔GUID binding fixes for debuffs *(2026-04-19)*
Three bugs in the plate-to-GUID resolution paths caused own debuffs to: not appear, vanish mid-duration, appear on the wrong target, and disappear when a plate re-entered view.

- **`AddOurStuffToPlate` (`core.lua:484`) was restricted to PLAYER/BOSS.** Regular NPCs whose plate-GUID binding hadn't been resolved yet by LibNameplate (i.e. you hadn't targeted or moused over them) fell through to `AddUnknownIcon` and their debuffs never showed via the name fallback. The restriction existed because mobs share names — but the codebase already has collision detection (`nametoGUIDs[name] = false`), which makes the type restriction redundant. Replaced with a `~= false` check so NPCs with unique names work too; ambiguous names still skip.
- **`ForceNameplateUpdate` (`combatlog.lua:339`) only handled players.** When you apply a debuff to an NPC, CLEU → `AddSpellToGUID` → `ForceNameplateUpdate`. It tried GUID lookup (fails when plate has no GUID binding), then fell through name fallback **only for players**. NPC debuffs never reached their plate until LibNameplate resolved the binding via target/mouseover. Extended to any GUID with name info, collision-aware.
- **Same function overwrote `nametoGUIDs[name]` unconditionally.** Even for players, this ignored the collision sentinel — if two players with the same name had both been seen, this code would overwrite the `false` back to a specific GUID, mis-attributing debuffs. Now merges with collision detection.
- **Simplified `LibNameplate_NewNameplate`:** the retry fallback here is now redundant with the fixed `AddOurStuffToPlate` and has been removed to avoid duplicate work and code-path divergence.

### Expected effect on the four symptoms
- **Don't appear:** NPC debuffs now resolve via name fallback when LibNameplate can't find the GUID binding.
- **Vanish mid-duration:** `ForceNameplateUpdate` after refresh/dose events now works for NPCs, so timer refreshes propagate back to the plate.
- **Wrong target:** collision detection now applies consistently across all paths; ambiguous names fail closed instead of mis-attributing.
- **Disappear on re-view:** plate re-show (`LibNameplate_NewNameplate`) now uses the same collision-aware name fallback for all types, so debuffs re-attach immediately instead of waiting for LibNameplate to re-resolve the GUID.

---

## NotPlater v1.3 — Fix NPC class coloring + MouseoverThreatCheck crash *(2026-04-19)*
Fallout from v1.2 surfaced two pre-existing bugs:

- **NPCs were getting class colors when targeted/moused-over/focused.** `UnitClass()` on an NPC mob returns valid class tokens like `"WARRIOR"` → `RAID_CLASS_COLORS["WARRIOR"]` is a valid color → NPC nameplate became brown. Existed before v1.2 but the buggy group-target branch was masking it by sometimes overwriting the color. v1.2 fixed that branch, which made the NPC coloring bug more visible.
  - Added `ResolvePlayerClassColor(unit)` helper that gates on `UnitIsPlayer()`. All four non-CLEU branches of `ClassCheck` now route through it. NPC → nil → nameplate keeps its default/threat color.
- **`threat-3.3.5.lua:258` double `.unitClass` extraction** (separate pre-existing bug): `local frame = healthFrame:GetParent().unitClass` assigned the color table to `frame`, then `frame.unitClass` was accessed — always nil (color tables have no `.unitClass` field), and crashed when the parent had no cached color under `useClassColors=true`. Changed to `local frame = healthFrame:GetParent()`.

Documented the remaining rare edge case (NPC sharing an exact name with a cached player → wrong CLEU fallback color) in code comments rather than adding complex mitigations; nameplate GUID caching isn't natively available on 3.3.5.

---

## NotPlater v1.2 — Class color fixes *(2026-04-19)*
Class colors on nameplates were slow to appear and sometimes showed the wrong class. Three issues fixed in `NotPlater-3.3.5.lua`:

- **Bug (wrong color):** `ClassCheck` line 182 read `UnitClass("target")` inside the party/raid-member target loop instead of `UnitClass(targetString)`. When a group member's target matched a nameplate, the class was taken from the **player's** target, not the matching unit — so enemies targeted by groupmates inherited the player's target class color.
- **Slow resolution for arbitrary enemies:** class previously only resolved via target/mouseover/focus/group-target matching. Added a `COMBAT_LOG_EVENT_UNFILTERED` listener that builds a `guidByName` + `classByGuid` cache from CLEU events — anyone who casts/hits/is-hit in your combat log range gets cached via `GetPlayerInfoByGUID`. `ClassCheck` falls back to this cache after the existing checks, so enemy players show correct class colors within 0.1s of the nameplate appearing.
- **Name-collision handling:** if two different GUIDs are seen for the same name, the name→guid entry is set to `false` (ambiguous), disabling the name-lookup for that name rather than returning a wrong class.
- **Nil-guard on `RAID_CLASS_COLORS[class]`** in case Ascension's custom classes return a non-standard class token.

Old behavior: enemy players often uncolored until you targeted them, and sometimes showed the wrong color when a groupmate was targeting them. New behavior: correct colors show as soon as the enemy has appeared in CLEU even once.

---

## TradeSkillMaster_Crafting v1.3 — Standalone queue delete *(2026-04-17)*
- **Fix:** Ctrl+Click and Shift+Right-Click now work in the **standalone `/tsm queue` window** too. v1.2 only patched the queue panel inside the main TSM craft-manager window — the standalone window had its own `OnCraftRowClicked` handler (line 2874) that was view-only aside from title-row collapse. Both handlers now share the same delete semantics.

---

## TradeSkillMaster_Crafting v1.2 — Cross-faction queue + Ctrl-Click delete *(2026-04-17)*
Ascension runs a unified cross-faction AH and a common workflow is "crafter on one faction, banker on the other." TSM's queue lives under `TSM.db.factionrealm.crafts[spellID].queued`, so switching faction showed an empty queue.
- **Realm-scoped storage:** in `OnEnable` after `AceDB:New`, lift `crafts`, `mats`, and `tradeSkills` into `TSM.db.realm` and reassign the `factionrealm` keys to point at the same Lua tables. All 184 existing `factionrealm.X` call sites keep working — the table they read is now shared across factions.
- **First-login merge:** non-destructive copy from `factionrealm` → `realm` (only fills missing keys), so existing scans survive. Idempotent; realm is authoritative from that point on.
- **Ctrl+Click removes row from queue** (`CraftingGUI.lua`): easier one-handed alternative to the existing Shift+Right-Click. Sets `queued = 0` and clears `intermediateQueued`. Tooltip hint updated to mention both.
- **Tooltip nil-cost guard** (`CraftingGUI.lua`): `TSM.Cost:GetCraftPrices()` returns nil when no mat prices are available; `FormatTextMoney(nil)` then returned nil and crashed the string concat. Now shows `---` instead of crashing.
- **Side effects:** SavedVariables writes the same blob into both the factionrealm and realm scopes on save (small disk overhead, no correctness issue). TSM core's operations/groups are still faction-scoped — if you run `Create Restock Queue` from a banker that doesn't have the operation, it won't queue anything. Manual queue edits and viewing work from either faction.

---

## AuxTSMBridge v1.1 — Cross-faction merge *(2026-04-17)*
Ascension runs a single unified AH, but aux stores history keyed by the scanning character's faction. The bridge previously only read the current character's faction, so switching factions hid half your scan history from TSM.
- **`GetAuxFactionTablesForRealm()`:** new helper that returns every faction table on the current realm
- **`GetAuxPricesDirect()`:** unions `data_points` across all faction scopes, takes `min(daily_min)`, then re-runs weighted-median on the combined set (sorted newest-first so the decay reference time is correct)
- **`SyncAuxToTSM()`:** iterates the deduped union of item_keys across factions; writes one merged entry per item into TSM AuctionDB
- **`GetAuxValue` / `GetAuxMinBuyout`:** dropped the `auxHistory.value()` / `market_value()` shortcut because those are faction-siloed — live TSM tooltips now use the merged direct parser too
- **`/axtsm status`:** lists per-faction counts plus the merged unique-item total
- Removed now-orphaned `GetAuxFactionKey()` helper

---

## AuxTSMBridge — Match aux's configurable decay *(2026-04-06)*
- Sync now reads aux's live `history_decay` setting (or `aux.account.history_decay`) instead of hardcoding `0.99`, so AuxMarket prices in TSM match aux's own % Hist. Value column

---

## unitscan — Skip instance dismiss cooldown when solo *(2026-04-06)*
- **`instance_dismiss()` solo guard** (`unitscan.lua`): the 1h pause-on-dismiss now only applies when actually grouped. If you're alone in the instance (no party/raid members), dismissing the popup no longer suppresses the scan

---

## PlateBuffs — Robust nameplate aura tracking *(2026-04-06)*
Fixes for "?" icons, debuffs falling off mid-timer, and debuffs never appearing.
- **Bypass LibAuraInfo gating** (`combatlog.lua` `LibAuraInfo_AURA_APPLIED`): when LibAI hasn't tracked an aura yet (cold cache, unfiltered spell), still add it using CLEU `auraType` + `GetSpellInfo` instead of silently dropping
- **GUID-based caster matching:** new `casterGUID` field on every entry; REMOVED/REFRESH/DOSE handlers match by `srcGUID` (always present in CLEU) instead of resolved name. Stops other players' debuff removes from stripping yours
- **Nil duration/expires guard** (`AddSpellToGUID`): normalize to `expirationTime=0` when unknown so `iconOnUpdate`'s `> 0` guard treats it as no-timer instead of dropping it next frame (was: `expires or 0 - 0.1` precedence bug = `-0.1`)
- **SPELL_PERIODIC_AURA_\* backup CLEU listener:** registered raw `COMBAT_LOG_EVENT_UNFILTERED` frame so periodic-prefixed bleeds/HoTs that LibAI doesn't dispatch still reach the apply path
- **Plate→GUID name fallback** (`LibNameplate_NewNameplate`): when a new plate has no GUID yet, look up `nametoGUIDs[name]` to attach buffs immediately. Populated opportunistically from CLEU dst names with collision detection (`= false` marker disables fallback for ambiguous names)
- **`/pb debug` toggle:** prints per-event combatlog tracing (apply source, refresh, remove) so the issue can be reproduced and inspected from chat

---

## FishingBuddy — Fix Astrolabe nil position crash *(2026-04-04)*
- **Nil position guard:** `GetCurrentPlayerPosition()` can return nil in unmapped zones or during loading — added early-return guards in `FishingSchools.lua` and `FishingExtravaganza.lua` to prevent arithmetic-on-nil crash in Astrolabe
- **ComputeDistance typo fix:** `FishingSchools.lua:56` passed `x, x` instead of `x, y` — fixed so pool proximity checks use correct coordinates

---

## Postal — Faster Open All Stuck Recovery *(2026-04-03)*
- **Reduced stuck detection timer:** from 5s to 1s — stuck mail items are now skipped after just 1 second instead of 5
- **Reduced refresh fallback timeout:** from 8s to 1s — if `MAIL_INBOX_UPDATE` never arrives, retry happens after 1 second instead of 8

---

## Aux-addon — Auctions Tab Letter-Key Navigation *(2026-04-02)*
- **Jump to item by letter:** Press a letter key in the Auctions tab to scroll to and select the first item starting with that letter
- **Multi-letter search:** Type quickly (within 1s) to narrow results (e.g., "WI" jumps to "Wintersbite")
- **Cycle on repeat:** Pressing the same letter again advances to the next matching item, wrapping around at the end

---

## Aux-addon — Auctions Tab Cancel Fixes *(2026-04-02)*
- **Scroll position preserved:** Canceling an auction no longer jumps the list back to the top; scroll offset is saved before rescan and restored after
- **Selection persistence fix:** `RemoveAuctionRecord` no longer calls `SetDatabase()` when the record was already removed by rescan, preventing the restored selection from being wiped by a stale callback
- **State machine bug fix:** Fixed undefined `cancel_in_progress` variable in `on_update` — now correctly calls `get_cancel_in_progress()` so the state machine waits for cancel to complete before re-scanning

---

## NotPlater — Threat Module Loading Fix *(2026-04-01)*
- **Nil unit guard (`threat-3.3.5.lua`):** Added `unit and UnitExists(unit)` check before `UnitDetailedThreatSituation` call to prevent crash when nameplates exist but units aren't valid yet (during/after loading screen)

---

## QuestRewardIcons — Quest Log Support *(2026-04-01)*
- **Quest log icons:** Gold/DE overlay icons now appear when browsing quests in the quest log, not just at NPC turn-in
- **Context detection:** Automatically uses `GetQuestLogItemLink`/`GetNumQuestLogChoices` for quest log, `GetQuestItemLink`/`GetNumQuestChoices` for NPC screens
- **New events:** Added `QUEST_DETAIL` (NPC accept screen) and `QUEST_LOG_UPDATE` (quest log selection) triggers

---

## FishingBuddy — Bug Fixes & Code Quality *(2026-03-31)*
- **Crash fix (`FishingSchools.lua`):** `for i in pairs(1,c)` → `for i=1,c do`; `pairs()` takes a table, not two numbers — this would crash on any call to `CollapseHoles()`
- **Nil guard (`FishingWatcher.lua`):** Wrapped `GetTime() - started` in `if started then` to prevent arithmetic-on-nil crash if `FISHING_DISABLED_EVT` fires out of order
- **Nil guard (`FishingBuddy.lua`):** Added `id and FishingBuddy_Info["Fishies"][id]` check before accessing nested table at `AddFishie()` line 755
- **Global leaks (`FishingInit.lua`):** `schools` and `temp` in `CopyFishSchools` / `RegisterFunctionTraps` declared `local`
- **Deprecated API (`*.lua`):** All `table.getn()` calls replaced with `#` operator (22 occurrences across 6 files)
- **Deprecated API (`*.lua`):** All `getglobal()` / `setglobal()` calls replaced with `_G[]` (30+ occurrences across 9 files); Libs folder untouched

---

## TitanPerformance v1.0 — Memory Monitor Integration *(2026-03-31)*
- **Memory monitor frame:** Left-clicking the Performance button now opens a full addon memory monitor instead of running garbage collection
- **Per-addon breakdown:** Scrollable, sortable list of all loaded addons showing current memory usage and growth since login
- **Leak detection:** Color-coded growth tracking (green < 2MB, yellow < 5MB, orange < 10MB, red > 10MB) with percentage growth in tooltips
- **Force GC button:** Garbage collection moved to a button inside the monitor frame
- **Reset Baseline button:** Restart growth tracking from current values at any time
- **Sortable columns:** Click column headers (Addon Name, Memory, Growth) to sort ascending/descending
- **Auto-refresh:** Updates every 5 seconds while the monitor frame is open

---

## TradeSkillMaster_Crafting v2.5.4 — Per-Item Queue Removal *(2026-03-31)*
- **Shift+Right-Click** on any craft in the queue panel removes that single item from the queue
- Tooltip hint added to queue rows showing the keybind
- Clears both `queued` and `intermediateQueued` state for the removed craft

## EpochFixes v1.1 — Quest Log Selection Drift Fix *(2026-03-31)*
- **Root cause found:** `pfQuest-epoch/pfQuest-nameplates.lua` `ScanQuestObjectives()` called `SelectQuestLogEntry()` on every quest in a loop without saving/restoring the selection, shifting the selected quest while the quest log was open
- **Three-layer fix in EpochFixes:**
  - (A) Guard `SelectQuestLogEntry`: blocks addon-driven calls (from Leatrix, pfQuest-epoch) when `QuestLogFrame` is visible
  - (B) Re-call `SetAbandonQuest()` in popup `OnAccept` to fix C++ internal state — `AbandonQuest()` reads from `SetAbandonQuest()`, not `GetQuestLogSelection()`
  - (C) Block ALL `SelectQuestLogEntry` calls while the abandon confirmation popup is open
- Added `OnHide` handler for popup dismissed via Escape key

## pfQuest-epoch v1.1 — Nameplate Scanner + Commission Quests + Chest Cleanup *(2026-03-31)*
- **Nameplate scanner fix:** `ScanQuestObjectives()` now saves/restores quest log selection around its iteration loop, preventing quest log drift
- **Commission quest visibility:** "Commission for..." quests now bypass the low-level quest filter on zone maps, minimap, and world map
- **Chest list cleanup:** Removed non-treasure entries from chest tracking (PvP supply crates, quest objects like Cat Figurine/Defias Gunpowder, Giant Clams, etc.)
- **Continent debug mode:** Added `epochDebugContinent` config option for debugging world map node rendering

## Aux-addon v1.1 — Auction Tooltip Fix *(2026-03-31)*
- **Tooltip hook fix:** Auction listing tooltips now use `SetHyperlink` instead of `load_tooltip`/`extend_tooltip`, so TSM and LibExtraTip price hooks fire correctly

## TitanGoldTracker v1.1 — BoP Item Detection *(2026-03-31)*
- **BoP/quest item detection:** New `GT_IsTradeable()` function checks items via hidden scan tooltip for "Binds when picked up" and quest item type
- **Accurate wealth tracking:** Untradeable items (BoP, quest items) now use vendor sell price instead of AH price for bag/bank value calculations
- New session caches: `GT_TradeableCache`, `GT_ScanTooltip`

---

## ArkInventory — Fix Bag Open/Drag Freeze *(2026-03-31)*
- **Removed redundant bulk category wipe** in `Frame_Main_Draw` that cleared `i.cat` on ALL items whenever any bag data changed
- `ScanBag` already clears `i.cat` per-item for changed items (line 1344); the bulk wipe in the draw path forced expensive tooltip scanning + PeriodicTable lookups for the entire inventory (~150-200 items) even when only 1 item changed
- This caused multi-second freezes on first bag open after login and on subsequent bag updates (BAG_UPDATE events from mail, AH, quest items, etc.)
- Full category wipe still occurs on rule/profile changes via `ItemCacheClear()` where it's actually needed

---

## BuffWatcher v1.0 — Per-Role Redesign *(2026-03-31)*
- **Complete rewrite:** BuffWatcher2 renamed to BuffWatcher; old BuffWatcher and BuffWatcher2 both deleted
- **Per-role buff configs:** 4 roles (Tank, Healer, Melee, Ranged) each with independent buff/consume entry lists
- **Talent-based spec detection:** Player's spec detected from talent tab point distribution; raid members inspected via `NotifyInspect()` queue (one at a time, 3s timeout, class-default fallback)
- **Spec → Role mapping:** Hardcoded defaults for all vanilla classes with TBC talents; user can override any spec's role in the Config panel (e.g. change Feral Druid from Melee to Tank)
- **Config UI:** UIDropDownMenu role selector at top; editing entries applies to the selected role only; "Spec Overrides" button opens side panel with click-to-cycle role buttons per class/spec
- **Status frame:** New Role column showing each player's detected role (colour-coded)
- **Export:** TSV now includes Role column; labels not applicable to a player's role show "-" instead of OK/MISSING
- **Migration:** Automatically imports old `BuffWatcher2DB` entries into all roles if present
- **Slash commands:** `/bw`, `/bw config`, `/bw check`, `/bw export`, `/bw inspect`, `/bw help`
- **Group events:** Re-inspects on `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE`

---

## Repo Cleanup *(2026-03-31)*
- **EpochFixes:** Known issues may be server-side rather than client-side; needs further investigation

---

## ArkInventory — Auto-Sell by Category *(2026-03-31)*
- **Auto-sell at vendor:** Items in categories flagged as "autosell" are automatically sold when opening a merchant window. Works with any item quality (grey, white, green, etc.)
- Per-category `autosell` flag stored in global SavedVariables (persists across characters)
- Checkbox added to custom category config panel (ArkInventory settings → Categories → Custom → [category] → "Auto-Sell at Vendor")
- Slash commands: `/arkinv autosell <name>` toggles auto-sell for a category, `/arkinv autosell list` shows enabled categories
- Chat summary printed after selling (e.g., "Auto-sold 5 item(s) for 1g 23s 45c")
- Files modified: `ArkInventory.lua` (DB defaults + AutoSellCategories function), `ArkInventoryStorage.lua` (MERCHANT_SHOW hook), `ArkInventoryConfig.lua` (UI checkbox + slash commands)

---

## TradeSkillMaster_Crafting *(2026-03-29)*
- **Leather intermediate-craft block:** Leatherworking queue no longer auto-crafts leather types (Light/Medium/Heavy/Thick/Rugged/Knothide/Borean Leather) as intermediate steps — they are treated as raw materials to buy/gather instead. Fixes Ruined Leather Scraps scrap-conversion recipe being incorrectly queued (`Queue.lua`: `LEATHER_BLOCKLIST`, `IsLeatherItem`, guard in `FindIntermediateSpellID`)

---

## NEW ADDONS (Created from scratch)

### BuffWatcher2 *(2026-03-29)*
- **Purpose:** Complete rewrite of BuffWatcher — configurable raid buff/consumable checker with Excel export
- Flat entry list: each entry maps a WoW buff name to an output label; entries sharing a label are grouped (any one match = requirement met)
- Two-column editable config frame: Buff Name | Output Label, with enable/disable checkbox and delete button per row
- TBC-focused defaults: Battle Elixir (7 elixirs), Guardian Elixir (4), Flask (4), Well Fed, plus world buffs
- **Export frame** (`/bw2 export`): produces tab-separated values (TSV) with one column per requirement label, pasteable into Excel via Ctrl+A, Ctrl+C
- Export includes ALL group members (OK/MISSING per label), sorted by most-missing-first
- Multi-line EditBox with "read-only" guard (OnTextChanged reverts edits) and Select All button
- Status frame: Player | Missing Buffs quick-glance view (only shows players missing something)
- Reset to Defaults button with StaticPopup confirmation dialog
- Draggable button with saved position, hover-to-open status, 5s auto-refresh
- Slash: `/bw2`, `/bw2 config`, `/bw2 check`, `/bw2 export`, `/bw2 help`
- Plain EditBox + backdrop Frame wrappers (avoids InputBoxTemplate auto-focus bugs from v1/v2)
- All state on `BW2` table, SavedVariables: `BuffWatcher2DB`

### BuffWatcher *(2026-03-27, updated 2026-03-27)*
- **Purpose:** Raid buff and consumable checker — converted from a WeakAura to a standalone addon
- Small draggable "BuffWatcher" button; hover (or left-click) opens the status popup
- Status popup auto-refreshes every 5 s while visible; mousewheel scrolls long results
- Categorises players into **MVPs** (flask + all buffs), **Greedy** (only missing flask), and **Missing** (detail view of every absent buff/consume)
- Per-class config in `BuffWatcher_Config.lua`: separate `worldbuffs` and `consumes` lists; any listed buff name counts as "present"
- Zandalar toggle: `/bw zan` or in-frame button excludes `zandalar = true` entries from checks
- Right-drag button to reposition; position persisted in `BuffWatcherDB`
- Slash: `/bw` toggle · `/bw check` force scan · `/bw zan` toggle Zandalar · `/bw help`
- Supports all vanilla classes: Warrior, Paladin, Hunter, Rogue, Priest, Mage, Warlock, Druid, Shaman
- Uses native 3.3.5 API: `UnitBuff()` index loop, `GetNumRaidMembers()`, `GetNumPartyMembers()`; no C_Timer
- **Fix (2026-03-27):** Moved all cross-file globals (`BW_Data`, `BW_ClassColors`, `BW_IsEnabled`) into the `BW` table (`BW.Data`, `BW.ClassColors`, `BW.IsEnabled`) to prevent clobbering by other addons sharing the global namespace — this was causing `BW_Data is nil` on every config-frame tab click

---

### QuestRewardIcons *(2026-03-27)*
- **Purpose:** Overlays small icons on quest choice reward items showing which has the best vendor or disenchant value
- Gold-coin icon on the item with the highest vendor sell price
- Enchanting icon on the item with the highest expected DE value
- Winner icon is larger (18px) with a coloured background (yellow=gold, blue=DE); loser is smaller (13px) and dimmed
- Gold wins if its value is ≥ DE value + 30s (configurable `GOLD_THRESHOLD`)
- DE values use a static lookup table by quality + item level bracket (Strange Dust through Abyss Crystal era); values tunable to server economy
- When best vendor and best DE item are the same button, both icons stack side by side
- Only activates when quest has ≥ 2 choice items; hooks `QuestInfo_Display` + `QUEST_COMPLETE`/`QUEST_GREETING` events

---

### DeleteItems
- **Purpose:** Complete ground-up rewrite of a basic item-deletion addon; full feature list below

**Core data layer**
- Three independent deletion lists (`list1`/`list2`/`list3`) stored in `DIData` (`SavedVariables` — account-wide, shared across all characters)
- Data migration path: old `DITotalSavedItems` / `DICurrentList` format automatically converted on first load
- String keys for all item IDs (prevents WoW SavedVariables numeric-key serialisation quirks)
- `activeList` persisted across sessions

**Main window**
- Scrollable item list with alternating row backgrounds, rarity colour-coding, and per-item vendor price shown inline
- Drag-and-drop zone: drag any item from bags directly onto the zone to add it to the active list
- Per-row `[Remove]` button; row tooltip shows the full item tooltip
- Three list-tab buttons at the top — **left-click** switches list, **right-click** opens a rename dialog (`StaticPopup` with `hasEditBox`)
- Per-list **notes** field (auto-saves on focus lost, Escape to revert, placeholder text)
- `[Delete Items From Bags]` button — requires **Shift+click** to confirm; tooltip shows live count of matching bag slots and total vendor value that would be destroyed
- `[Clear List]` button with confirmation popup
- `[Scan Bags for Junk Suggestions]` button to open the junk scanner

**Launcher button**
- Small draggable frame button always visible on screen (replaces minimap button)
- **Hover tooltip:** shows active list name, number of matching bag slots that would be freed, and total vendor value to be destroyed
- **Click:** toggle the main window open/close
- **Shift+click:** delete immediately without opening the window
- Drag to reposition anywhere on screen

**Junk scanner**
- Separate draggable frame (430 px wide) anchored to the right of the main window
- **Threshold control:** `Max sell price (gray/white):` edit box (silver) — `0` shows all grays regardless of price; `> 0` shows gray and white items whose sell price per item is ≤ the threshold
- `[Scan Bags Now]` button — reads current threshold, scans all bags, results sorted cheapest first
- Per-row layout: item icon + name (quality colour) on line 1; formatted vendor price/ea + bag count + max-stack hint on line 2; stacked `[Add to List]` and `[Ignore]` buttons on the right
- `[Add All Suggestions to Active List]` — bulk-adds all current results
- Per-item **Ignore** button: adds item to `DIData.junkIgnore`; ignored items never appear in future scans
- `[Clear Ignored Items (N)]` button — shows live count, disabled when list is empty
- Items already in any deletion list are automatically excluded from scan results
- Object pooling (`junkRowPool`) for efficient re-renders

**Slash commands**
- `/di` — open/close window
- `/di add <id|link>`, `/di rem <id>`, `/di del`, `/di list`, `/di clear`
- `/di set list1|list2|list3`, `/di junk` — open junk scanner

### TitanSpeed
- **Purpose:** Titan Panel plugin that displays the player's current movement speed as a percentage
- Detects active speed buffs (Druid forms, Sprint, Ghost Wolf, mounts, speed potions)
- Shows yards/sec and active speed sources in tooltip
- Polls every 0.2 seconds via `OnUpdate`
- **Speed buff display:** tooltip now shows each active speed buff with its bonus percentage, e.g. `Cat Form (+30%)`, `Sprint (+70%) - 9s`; rank-varying spells (Sprint, Dash) resolve the correct % from the rank string returned by `UnitBuff`; timed buffs show remaining seconds

### EpochFixes
- **Purpose:** Patches four distinct client bugs specific to the Ascension/Epoch environment
- **Fix 1 — SpellBook tab:** Wraps `OnEnter` handler in `pcall()` to suppress nil concatenation error when `TOGGLEPETBOOK` keybind is unassigned
- **Fix 2 — Quest abandon:** Hooks `QuestLogAbandonButton:OnClick` to snapshot the quest log selection index; wraps `StaticPopupDialogs["ABANDON_QUEST"].OnAccept` to call `SelectQuestLogEntry(savedIndex)` just before `AbandonQuest()` runs — guarantees the right quest is selected at the last possible moment regardless of what other addons (e.g. Leatrix auto-quest scan via `SelectQuestLogEntry` loop) did to the selection while the popup was open; works in tandem with pfQuest-wotlk/quest.lua raw-override fixes
- **Fix 3 — Quest reward tooltips:** Hooks quest item `OnEnter` events to reclaim `GameTooltip` ownership when pfQuest or Leatrix corrupt the tooltip anchor state
- **Fix 4 — Inspect tooltips:** Caches all 19 equipped item links on `INSPECT_READY`; falls back to cached links after API returns nil (~10–15 seconds after cache expiry)

### AuxTSMBridge
- **Purpose:** Two-way price data bridge between Aux auction scanner and TradeSkillMaster
- Registers two TSM price sources: `AuxMarket` (weighted median) and `AuxMinBuyout` (daily low)
- Auto-syncs all Aux scanned prices into TSM AuctionDB when the Auction House closes (throttled to once per 12 real hours, persisted across sessions via `AuxTSMBridgeDB` SavedVariable)
- Calculates weighted median with exponential time decay (0.99^days_ago), replicating Aux's own algorithm
- Parses Aux's raw history strings directly instead of calling `auxHistory.value()` in a loop — the latter goes through Aux's temp-table allocator (`T.lua`) and causes `memory allocation error: block too big` when called thousands of times synchronously outside Aux's execution context
- Slash commands: `/axtsm sync` (force immediate sync, resets the 12-hour timer), `/axtsm status`

**Bug fixes:**
- `quantity = 0` written during sync encoded to TSM's sentinel `"~"` which decodes back to `nil`; TSM's tooltip then calls `format("%d auctions", nil)` and crashes — fixed by defaulting to `1` in the bridge and adding `or 0` guard directly in `TradeSkillMaster_AuctionDB.lua` line 295
- `AUCTION_HOUSE_CLOSED` fires twice in 3.3.5 (Aux hides its frame in the same event, re-triggering it); the 12-hour cooldown naturally absorbs the double-fire
- Removed noisy login message "Registered AuxMarket and AuxMinBuyout as TSM price sources"

---

## PORTED ADDONS (Modified for 3.3.5a compatibility)

### NotPlater-3.3.5
**Bug fix — "Usage: UnitDetailedThreatSituation" error (`modules/threat-3.3.5.lua`):**
- `GetThreat` and `GetMaxThreatOnTarget` called `UnitDetailedThreatSituation` unconditionally; compound unit tokens like `"pet-target"` and stale/non-existent units cause the API to throw a hard Lua error in combat
- Fixed by adding `UnitExists()` guards in both functions before calling the API; invalid units return `nil`/`0` safely instead

**Bug fix — login crash "table index is nil" (`modules/threat-3.3.5.lua:80`):**
- `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE` are called from `OnInitialize` before `PLAYER_LOGIN`, at which point `UnitGUID("player")` returns nil — using nil as a table key is a hard Lua error
- Fixed by storing all `UnitGUID()` calls in locals and nil-checking before assigning: `playerGuid`, `UnitGUID("party"..i)`, and `UnitGUID("raid"..i)` all guarded

**Bug fix — "High Threat" color never displayed (`modules/threat-3.3.5.lua`):**
- `lastThreat` was keyed by volatile unit-ID strings (`"mouseover"`, `"party1-target"`, etc.) which change between calls, so the threat-trajectory comparison (`highestThreat - (playerThreat + 3*(playerThreat - lastThreat[unit]))`) always saw `nil` and skipped the High Threat (c2) state entirely
- Fixed by adding `healthFrame.lastUnitGuid` (stable GUID) stored alongside `lastUnitMatch` at all three match sites (`group target`, `mouseover`, `focus`) in `ThreatCheck`, in `MouseoverThreatCheck`, and cleared in `ThreatComponentsOnShow`
- `lastThreat` now keyed and read by GUID instead of unit-ID string

**Bug fix — `MouseoverThreatCheck` ignored its `guid` parameter:**
- Was always setting `lastUnitMatch = "mouseover"` and discarding the passed-in `guid`; now also sets `lastUnitGuid = guid` so the stable key is available for `lastThreat`

**Bug fix — `tgetn(group)` on a hash table always returned 0:**
- `group` is keyed by GUID (hash table), so `table.getn` always returned 0, making the number-text ranking threshold division wrong
- Replaced with `groupSize` counter incremented inside the existing loop, with a `groupSize > 1` guard

**Bug fix — `ThreatComponentsOnShow` crash on login ("Font not set"):**
- `SetText("")` was called on FontStrings before `ConfigureThreatComponents` had set their font, causing a Lua error on every nameplate shown at login
- Fixed by guarding with `if healthFrame.threatDifferentialText:GetFont() then`

**Feature — solo play support (Hunter pet threat):**
- `PARTY_MEMBERS_CHANGED` now always builds `self.party` (previously `nil` when solo), always including `"player"` and `"pet"` if present
- `ThreatCheck` and `MouseoverThreatCheck` gate changed from `UnitInParty/UnitInRaid` check to `if group then`, so solo always runs the full threat path
- Solo correction in `OnNameplateMatch`: `UnitDetailedThreatSituation` for the pet may return `nil` when not in a party/raid, causing `highestThreat == playerThreat` and always showing c1; fixed by reading the player's own `status` field (0/1 = not tanking, 2/3 = tanking) and bumping `highestThreat` when the API confirms the player is not the aggro holder

### ItemRack (v2.243)
**New Feature — "Disable in BG/Arena" per-set option:**
- Added `NoBG` flag to the set data structure (`ItemRackUser.Sets[name].NoBG`)
- `ItemRackEvents.lua`: Checks `inPVP` + `NoBG` flag before equipping in all three event processors — stance events (line 324), zone events (line 360), and buff events (line 397)
- Prevents any automatic set equip trigger while player is inside a battleground or arena

**Bug fix — trinket autoqueue cross-slot stop:**
- `ItemRackQueue.lua` `ProcessAutoQueue()`: added paired-slot buff check using `SlotInfo[slot].other`
- When either trinket fires and its buff becomes active, the *other* trinket's queue now also pauses — preventing unnecessary swaps during the 20-second shared trinket cooldown
- Fix is symmetric: works regardless of which trinket (slot 13 or 14) was used first

### ItemRackOptions (v2.243)
**New Feature — "Disable in BG/Arena" checkbox in Sets panel:**
- Added `"Disable in BG/Arena"` label string to `ItemRack.CheckButtonLabels`
- Added `ItemRackOptSetsNoBGCheckButton` (20×20, `ItemRackOptSimpleCheckButton` template) anchored below the Hide checkbox in `ItemRackOptSubFrame2`
- `ItemRackOpt.NoBGSet()` function reads checkbox state and writes/clears `NoBG` on the active set
- Checkbox is disabled when no set is selected; enabled and synced to saved value when a set is loaded
- Increased Sets panel frame height to accommodate new checkbox

**Bug fix — "stop queue here" always available for all slots:**
- `PopulateSortList()`: unconditionally calls `AddToSortList(sortList, 0)` after the item loop
- Previously the `0` sentinel ("-- stop queue here --") was only added when `AllowEmpty=="ON"` AND the slot had an item equipped AND the bank was closed — meaning slot 14 (bottom trinket) would often be missing the stop marker
- Since `AddToSortList` deduplicates, this is safe to call unconditionally and decouples queue-control from the empty-slot-in-menu setting

### FavoriteContacts (v2.13.1) — Ported from Retail 12.0
**API compatibility fixes:**
- Replaced `C_AddOns.GetAddOnMetadata` → `GetAddOnMetadata`
- Replaced `Settings.RegisterAddOnCategory` → `InterfaceOptions_AddCategory`
- Replaced `Settings.RegisterCanvasLayoutCategory` → standard options frame registration
- Added double-call of `InterfaceOptionsFrame_OpenToCategory()` to work around 3.3.5 panel focus bug
- Guarded `slider:SetObeyStepOnDrag()` — not available in 3.3.5

**UI framework compatibility (XML / Lua):**
- Replaced `parentKey` attribute (retail-only) throughout all XML with `name="$parentXxx"` naming; all child access updated to `_G["ParentNameXxx"]` pattern
- Replaced `relativeKey` anchor references with explicit `relativeTo="globalName"` in all `<Anchor>` elements
- Removed `inherits="SelectionFrameTemplate"` (retail-only); `OkayButton` and `CancelButton` created programmatically via `UIPanelButtonTemplate` instead
- `UIRadioButtonTemplate` child FontString: `parentKey` is ignored in 3.3.5; buttons explicitly named `FavoriteContactsRadioButton1…N` and `.text` assigned via `_G[name.."Text"]`
- Replaced `SetSize(w,h)` → separate `SetWidth()` / `SetHeight()` calls throughout
- Removed 5th `CreateFrame` argument (not supported in 3.3.5)
- `FauxScrollFrame_GetOffset()` returns nil before first scroll in 3.3.5 — added `or 0` at both call sites
- Removed the `ListScrollFrameTemplate` ScrollFrame from the icon picker entirely — 56 icons fit in 8×7 slots without scrolling, making `FauxScrollFrame_Update` and its `_G[name.."ScrollBar"]` lookup unnecessary; `scrollOffset` hardcoded to `0`

**Contact button container (`ContactContainer.lua`):**
- Added dark `SetBackdrop` (tooltip textures) with `SetBackdropColor(0,0,0,0.85)`; grey border when locked, gold border when unlocked
- `SetMovable(true)` + drag support: container moves freely when unlocked; position saved to `settings.posX`/`settings.posY` via `GetLeft()`/`GetTop()` on `DragStop`
- Right-click toggles `settings.locked`; border colour updates immediately
- Removed all `OpenMailFrame:ClearAllPoints()`/`SetPoint()` calls — repositioning mail child frames externally breaks 3.3.5 mail UI layout

**Settings (`Settings.lua`):**
- Default `scale` changed from `"AUTO"` to `0.75` (AUTO scaled buttons to fill MailFrame height, making them oversized)
- Added `locked = true`, `posX = false`, `posY = false` to `defaultSettings` and `ResetUISettings`

**Icon palette (`EditPopup.lua`):**
- Replaced all `ClassIcon_*` (not in this client's MPQ) and `ability_*`/`spell_*` class icons (unreliable in this client) with `inv_*` item icons present in vanilla WoW 3.3.5
- Vanilla classes only (no Death Knight): Warrior `inv_sword_04`, Paladin `inv_hammer_01`, Hunter `inv_weapon_bow_07`, Rogue `inv_weapon_shortblade_05`, Priest `inv_staff_01`, Shaman `inv_jewelry_talisman_04`, Mage `inv_wand_07`, Warlock `inv_staff_09`, Druid `inv_misc_monsterclaw_04`
- Race icons use `achievement_character_*` (WotLK achievement icons, confirmed working in this client): 10 Alliance + 8 Horde races
- Profession icons: `Trade_*` and `inv_*` prefixes (confirmed working) — Alchemy, Blacksmithing, Enchanting, Engineering, Herbalism, Inscription, Jewelcrafting, Leatherworking, Mining, Skinning, Tailoring, Fishing, Cooking, First Aid
- Miscellaneous icons: bags, bank/vault, key, note, PvP banners (`INV_BannerPVP_01/02`)
- Added type guards on saved position coordinates (`type(posX) == "number"`)

### TradeSkillMaster_Crafting (v2.5.2)
**New Feature — Vellum support for enchanting crafts:**
- Added `VellumInfo.lua`: lookup table mapping enchanting spell IDs to the correct vellum item IDs (38682, 37602, 39349, 39350, 43145, 43146)
- Added `CheapestVellum()` function: automatically substitutes a lower-tier vellum with Vellum III when it's cheaper; guards against `nil` returns from `GetItemInfo()`
- Vellum cost integrated into crafting cost display and tooltip breakdown
- `OnEnable()` migration routine: fixes legacy vellum item string formatting in saved DB (converts bare item IDs to full `item:id:0:0:0:0:0:0` format)

**Crafting queue — intermediate craft flattening overhaul (`Queue.lua`):**
- Added `FindIntermediateSpellID(itemString)` helper: finds the best spell for crafting an item as an intermediate; tries cost-based `GetLowestCraftPrices` first, falls back to direct `craftReverseLookup` scan when pricing data is absent (e.g. items with no AH data on the private server); prefers non-cooldown crafts
- `GetIntermediateCrafts`: replaced the old `craftCost and lowestCost and craftCost <= lowestCost` gate — intermediates are now always expanded whenever a known craft exists, not only when TSM pricing data is available; uses `FindIntermediateSpellID`
- `HasLoop`: updated to use `FindIntermediateSpellID` so loop detection mirrors the new expansion logic
- Bug fix: `usedMats` re-add at end of `GetQueue()` now skips zero-quantity entries; previously an intermediate craft with zero inventory would be re-inserted into the materials table with `quantity = 0`, causing it to appear in the materials list as "Need 0 / Total 0"
- Materials calculation reverted to always use full `data.queued` (removed an earlier `effectiveQueued` reduction that caused materials to show Total = 0 when result items were stocked on any character)
- Added `HasPoorQualityMat(spellID)` guard: skips any intermediate craft whose mats include a gray (quality 0) item — prevents scrap-conversion recipes (e.g. 5x Ruined Leather Scraps → Light Leather) from being used as intermediates; regular leather types are shown as-is in the materials list instead

**Crafting queue — alt-stock awareness (`CraftingGUI.lua`):**
- Queue display now shows `(X stocked, craft Y)` annotation next to each craft name when `GetTotalQuantity` detects you already have some of the result item across all characters; correctly reduces the "effective crafts needed" count in the annotation without affecting the materials list
- Bug fix (`UpdateQueue`): `TSM.db.factionrealm.tradeSkills[UnitName("player")]` nil-guarded with `or {}`; previously crashed when a character that had never scanned professions with TSM opened the queue panel (e.g. a bank alt opening First Aid)

**New slash command — `/tsm queue` (`TradeSkillMaster_Crafting.lua`):**
- Added `/tsm queue` slash command that opens/closes the standalone crafting queue window; works from any character, not just those who have scanned professions

### TradeSkillMaster_AuctionDB (v2.3.10)
**Bug fixes — data encoding guards:**
- Added nil and empty-string guards in `decodeScans()` to prevent corruption when day or market value data fails to decode
- Double-validates decoded `day` value before creating scan entries

**Custom data parsing:**
- Added `DecodeJSON()` function using `gsub()` + `loadstring()` to parse JSON-like app data into Lua tables
- Supports realm/faction data merging with multi-hyphen realm name parsing
- Accepts cross-faction auction data imports within a configurable `MAX_AVG_DAY` time window

**AuxTSMBridge compatibility fix:**
- Added `or 0` guard on `TSM.data[itemID].quantity` in `GetTooltip()` (line 295) — AuxTSMBridge writes synced items with no auction count; TSM's `encode(0)` stores `"~"` which decodes to `nil`, causing `format("%d auctions", nil)` to crash on item hover

### ArkInventory
**Ace3 library xpcall fix (Lua 5.1 / 3.3.5 compatibility):**
- All embedded Ace3 libraries (AceGUI-3.0, AceAddon-3.0, AceTimer-3.0, AceConfigDialog-3.0, AceBucket-3.0, CallbackHandler-1.0) use the `CreateDispatcher(argCount)` pattern — generates closures via `loadstring` that capture arguments before calling `xpcall(call, errorhandler)` with no extra args, working around the 3.3.5 limitation where `xpcall(f, h, ...)` silently drops variadic arguments

**Suppress spurious login warning (`ArkInventory.lua`, `ArkInventoryUpgrades.lua`):**
- Root cause: `GetContainerNumSlots` returns 0 for some bags during the first scan on login (timing race — bags not fully initialised before the scan fires); the addon was logging `WARNING> aborted scan of bag N, location 1 [Bag] size returned was 0` on every login
- `ArkInventory.lua` line 1291: changed default for `option.bugfix.zerosizebag.alert` from `true` to `false` so new characters / fresh profiles start with the warning suppressed
- `ArkInventoryUpgrades.lua` line 1235: changed the upgrade migration that ran on every load from forcing `zerosizebag.alert = true` to `false`, so existing profiles no longer have the warning re-enabled on each reload

**Bank window zone layout fix (SavedVariables — Default profile):**
- Root cause: the bank window (location index `3` per `ArkInventory.Const.Location.Bank = 3`) had no `["bar"]["data"]` table, only `["per"] = 6`, so it displayed 6 unnamed default zones instead of the configured 10
- Fixed `WTF/Account/DEFCON/SavedVariables/ArkInventory.lua`: replaced the minimal bank bar config in the Default profile's `["location"][3]` entry with the full 10-zone definition matching the regular inventory: Junk, Trash, Quest, Consume, Div, Value, DE, Equip, Trinket, Ammo
- Also copied the full category rule table from the bags location so items sort into the same zones in the bank as they do in regular inventory

**Aux / TSM price rule functions (`ArkInventoryRules.lua`):**
- Added aux market price rules using `TSMAPI:GetItemValue(link, "AuxMarket")` (requires AuxTSMBridge) with a direct `aux.faction` history fallback if TSM is absent; gracefully returns `false` when neither addon is loaded
  - `auxpriceunder(copper)` / `apu(copper)` — true if aux market price ≤ threshold
  - `auxpriceover(copper)` / `apo(copper)` — true if aux market price ≥ threshold
- Added TSM arbitrary price-source rules via `TSMAPI:GetItemValue(link, source)`:
  - `tsmpriceunder("source", copper)` / `tpu("source", copper)` — true if named TSM price source ≤ threshold
  - `tsmpriceover("source", copper)` / `tpo("source", copper)` — true if named TSM price source ≥ threshold
  - Works with any registered TSM source key: `"DBMarket"`, `"DBMinBuyout"`, `"AuxMarket"`, `"AuxMinBuyout"`, etc.
- Added `auxovervendor(percent)` / `aov(percent)` — true if aux market price ≥ vendor sell price × (1 + percent/100); e.g. `aov(50)` flags items where AH price is at least 50% above vendor
- Added `deovervendor(copper)` / `dov(copper)` — true if TSM disenchant value exceeds vendor sell price by at least `copper`; uses `TSM:GetDisenchantValue` via AceAddon lookup (no `TSM` global required); returns `false` gracefully if TSM is not loaded
- Added `dedbg()` — debug helper rule that prints vendor price, aux market price, and DE value (with price source) to chat for every item evaluated; always returns false; useful for diagnosing price rule issues
- All functions guard against missing addons (nil checks on `TSMAPI`, `LibStub`, `aux`) — safe to use in an ArkInventory installation without TSM or aux

**Suppress item-cache warning on login (`ArkInventoryStorage.lua`):**
- `GetItemInfo` returns empty strings for type/subtype during the brief post-login window before the client has cached all item data; ArkInventory was printing `WARNING> <temporary> item cache not updated yet` for each affected slot
- Suppressed the warning for the `t == "" and s == ""` case — the slot is correctly handled as `Slot.Type.Unknown` and re-evaluated on the next scan; the "missing translation" warning for genuinely unknown types is preserved

### Magnify-WotLK
**3.3.5 API compatibility:**
- Settings panel uses `InterfaceOptions_AddCategory` / `InterfaceOptionsFrame_OpenToCategory`
- All hooking via `hooksecurefunc()` — no `CreateFromMixins` or `EventRegistry`
- Textures use `CreateTexture()` + `SetTexture()` — no `SetAtlas` or `SetColorTexture`

**Bug fix — zone navigation always landing on the player's current zone:**
- Root cause: `Blizzard_BattlefieldMinimap.lua` registers a `WORLD_MAP_UPDATE` handler that calls `SetMapToCurrentZone()`, overriding any `SetMapZoom()` call made during navigation
- Secondary issue: WoW 3.3.5's game loop runs `OnUpdate` scripts *before* dispatching queued game events, so an `OnUpdate`-based suppression flag clears too early and lets the reset through
- Added `MagnifyNavigateMap()` to replace `WorldMapButton_OnClick` for continent→zone and world→continent clicks: matches `WorldMapFrame.areaName` (set by `UpdateMapHighlight` in `OnUpdate`) against `GetMapZones()` / `GetMapContinents()` and calls `SetMapZoom()` directly, bypassing the game's click handler which does not account for Magnify's scroll frame
- Added `SetMapToCurrentZone` wrapper with a `Magnify_SuppressMapReset` flag; flag is cleared in a `WORLD_MAP_UPDATE` event listener registered after BattlefieldMinimap loads, so our handler fires *after* BattlefieldMinimap's reset call is suppressed
- Added empty `OnClick` handler on `WorldMapButton` to prevent the game's native click event from firing `WorldMapButton_OnClick` a second time after `OnMouseUp` already handled navigation
- `SetDetailFrameScale` (which internally calls `WorldMapFrame_OnEvent`) is now only called when `WorldMapScrollFrame.zoomedIn` is true, preventing spurious map resets on every plain click

### HCBreathBar
- Ported from Classic Era (Interface 11403 → 30300); removed `SOUND_CHANNEL` arg from `PlaySound` (not supported in 3.3.5)
- Default sound changed from numeric ID 12889 (Classic Era only) to `"igQuestComplete"` string, which is valid in 3.3.5
- `self.value` on MirrorTimer frames is already in **seconds** in 3.3.5 (dividing by 1000 caused always-zero display; reverted)
- `MirrorTimer1`/2/3 are plain `Frame` widgets in 3.3.5, not `StatusBar` — `SetStatusBarTexture` doesn't exist on them; styling via child-find approach also failed because the game resets child bar properties each tick
- Final fix: hide the original frame with `SetAlpha(0)` on first BREATH detection; overlay our own fully-controlled `StatusBar` frame anchored to the same position; restore alpha on `MIRROR_TIMER_STOP`
- Minimalist look: flat `WHITE8X8` texture fill, dark semi-transparent trough, no border, wide bar (420×14 px)
- Sound switched to `PlaySoundFile("Sound\\Interface\\AlarmClockWarning1.wav")` — `PlaySound` string form unreliable in 3.3.5; file path is guaranteed present since TBC/WotLK; alert rate doubles when breath < half threshold
- Bar max duration now captured from `MIRROR_TIMER_START` event args rather than `self.maxValue` frame field (field absent/wrong-cased in 3.3.5 causing bar to default to 3-min scale regardless of actual breath pool); normalises ms→s if value > 600
- Font changed from `ARIALN.ttf` 11 px `OUTLINE` to `FRIZQT__.ttf` 13 px `THICKOUTLINE` — heavier outline needed for legibility against the blue fill

### FeralAPFix
- Wraps `GameTooltip:SetHyperlink()` with a nil guard — prevents crash when Ascension's built-in `feral-attack.lua` calls `GetItemInfo(link)` with a nil link triggered by TSM's LibExtraTip tooltip callbacks
- Hook moved to top-level file load (no longer deferred to `PLAYER_LOGIN`) so the guard is in place before TSM or any other addon fires `SetHyperlink(nil)` during the login sequence

### unitscan
- Uses `GetBuildInfo()` build detection (`isWOTLK = build == 30300`) for version-specific UI code
- `LibCompat-1.0` backport library included: provides `IsInRaid()`, `IsInGroup()`, `GetNumGroupMembers()`, `UnitIterator()`, `GetUnitIdFromGUID()` for 3.3.5
- `LibCompat-1.0` uses `pcall` (not `xpcall`) in `QuickDispatch()` — correct for Lua 5.1
- Class color system checks for `CUSTOM_CLASS_COLORS`, falls back to `RAID_CLASS_COLORS`; manually adds missing `colorStr` fields including Death Knight
- `UPDATE()` now returns early on `InCombatLockdown()` before any scan loop runs, preventing `ADDON_ACTION_BLOCKED` spam from `TargetUnit()` being called in combat (taxi/flight early-return was already present but the combat guard only covered `discovered_unit`, not the main scan)

**Feature — combat-safe close button:**
- Close button replaced from `UIPanelCloseButton` to `SecureHandlerClickTemplate` with `SetAttribute("_onclick", "self:GetParent():Hide()")` — allows hiding the popup while in combat lockdown without triggering "Interface action failed" errors

**Feature — dead mob cooldown tracking (`unitscan_dead` SavedVariable):**
- Mobs confirmed dead or corpse are put on a respawn cooldown and skipped from scanning; popup auto-hides when the mob is found dead
- Cooldown is per-mob: reads respawn time in seconds from pfQuest's unit database (`pfDB["units"]["data"][id]["coords"][n][4]`) via a reverse name→ID lookup cache built at `PLAYER_LOGIN`; falls back to `DEAD_COOLDOWN_HOURS` (default 8h) if pfQuest has no data
- `unitscan_dead` stored as `{ t=timestamp, secs=respawn_seconds, from_pfquest=bool }` per mob; persists across sessions via `SavedVariables`; old plain-timestamp entries auto-migrated on load
- Default cooldown changed from 2h to 8h (correct baseline for WotLK outdoor rares); configurable via `/unitscan cooldown <hours>`
- Dead detection moved entirely to `checkTargetDead()` called from `PLAYER_TARGET_CHANGED` and `UNIT_HEALTH` events — removed from the `TargetUnit()`/`forbidden` scan loop which was unreliable (in combat `TargetUnit` doesn't switch target, so `UnitIsDead("target")` read the wrong unit)
- `checkTargetDead()` guards: verifies `UnitName("target")` matches the tracked mob name before acting; skips entirely inside instances (`IsInInstance() ~= "none"`) — instance mobs reset on every run
- `/unitscan cooldowns` — lists all mobs on dead cooldown with time remaining; shows `[pfQ]` tag when timer came from pfQuest database
- `/unitscan cooldown <hours>` — sets the fallback respawn cooldown for mobs not in pfQuest's database
- Chat notifications on death detection ("is dead. Pausing scan for Xh.") and cooldown expiry ("cooldown expired. Resuming scan.")
- `unitscan_defaults` keys backfilled on load to handle SavedVariables from older versions missing new keys (fixes "attempt to perform arithmetic on field 'DEAD_COOLDOWN_HOURS' (a nil value)")

**Feature — pfQuest map icon integration:**
- When a rare is detected dead, its `/db track rares` map icon is immediately removed via `pfMap:DeleteNode("TRACK_RARES", name)` + `pfMap:UpdateNodes()`
- `pfMap:UpdateNodes` is hooked so the icon stays hidden on every map open/refresh while cooldown is active; restores automatically when cooldown expires
- All pfMap calls nil-guarded — silently no-ops if pfQuest is not installed or rares tracking is disabled

**Feature — instance dismiss cooldown:**
- Clicking the X button (or right-clicking) the popup while inside any instance applies a 1 hour cooldown so the same mob won't alert again for the remainder of the session
- Implemented via `PreClick` on the close button (fires before the secure `_onclick` hide, so `button:GetText()` is still valid) and `PostClick` on the main button for the right-click path
- Only triggers inside instances (`IsInInstance() ~= "none"`); open-world dismissals are unaffected

### pfQuest-epoch
**New feature — Rares/Chests toggle buttons on the WorldMap (`pfQuest-worldmap.lua`):**
- Two small toggle buttons (76×16 px, custom backdrop) anchored inside `WorldMapPositioningGuide` top-right, below the close/arrow buttons, with no gap between them
- **Rares** button and **Chests** button each toggle their respective `pfDatabase:TrackMeta()` tracking on/off with a single click; label and backdrop colour update to reflect current state (green = ON, dark = OFF)
- Tooltip on hover shows current state and equivalent slash command (`/db track rares` / `/db track chests`)
- Syncs with slash-command state changes via `WORLD_MAP_UPDATE` event (safe — does not hook `WorldMapFrame_Update` or `SetScript OnShow`, both of which break `SetupFullscreenScale` in 3.3.5)
- Buttons use `SetFrameStrata("DIALOG")` + `SetFrameLevel(100)` so they remain clickable in windowed map mode

- Epoch-specific NPC/quest database layered over pfQuest-wotlk via `patchtable()` merge system
- `overwrites.lua` removes content not present on Epoch (Silithus NPCs, TBC quest givers, Zul'Aman island)
- Version checking via `GetAddOnMetadata()` with addon messaging for update notifications
- Update notifications (`pfQuest-epoch.lua`, `pfQuest-updater.lua`) now gated behind `pfQuest_config["updatenotify"]` — default off; only print if config key is explicitly `"1"`

### pfQuest-wotlk
- Added `"Cut-Out Range (yards, 0=always)"` text field to `pfQuest_defconfig` (config key `cutoutminimaprange`, default `"0"`); when non-zero, minimap cut-out icons are only rendered within that yard radius of the player — avoids icon clutter at map edges
- `pfMap:UpdateNode` gains a `yards_distance` parameter; `UpdateMinimap` converts pixel distance to yards (`distance * mapZoom / drawlayer:GetWidth()`) and passes it through for the range check
- Added `"Show Update Notifications"` checkbox to `pfQuest_defconfig` (config key `updatenotify`, default `"0"` / off); controls whether pfQuest-epoch version-available messages appear in chat
- Multi-client compatibility layer (`compat/client.lua`): detects build version and maps API differences between Vanilla/TBC/WotLK
- `string.gmatch or string.gfind` fallback for Lua 5.0 vs 5.1
- `mod or math.mod` fallback for math function rename
- Quest frame name mappings for 3.3 renames (`QuestLogQuestTitle` → `QuestInfoTitleHeader`, etc.)
- `QuestWatchFrame` vs `WatchFrame` handled per client version
- Item link suffix format differs per client (`":0:0:0"` vs `":0:0:0:0:0:0:0:0"`)
- Wowhead database URL selected per client (wotlk/tbc/classic)

**Bug fixes — quest log raw override removal (`quest.lua`):**
- Replaced raw `AbandonQuest = function()` global override with `QuestLogAbandonButton:HookScript("OnClick")` — the override was calling `GetAbandonQuestName()` at confirm time, which could return a stale/wrong quest if another addon (e.g. Leatrix auto-quest scan) called `SelectQuestLogEntry()` while the confirmation popup was open; hooking the button captures the name at click time before any event can shift the selection
- Replaced raw `QuestLog_Update = function()` global override with `hooksecurefunc("QuestLog_Update", ...)` — the raw replacement was creating a tainted version of this function, which on 3.3.5 can prevent `QuestLogAbandonButton` (controlled by `QuestLog_Update`'s call chain) from responding to clicks
- Replaced raw `QuestLogTitleButton_OnClick = function()` global override with `hooksecurefunc("QuestLogTitleButton_OnClick", ...)` for the same taint reason

### Postal
**Open All — reliability and speed improvements:**
- Fixed `updateFrame` event handler: on `MAIL_INBOX_UPDATE`, the timer is now accelerated to 0.05 s instead of calling `ProcessNext()` directly; calling `TakeInboxItem` inside an event handler chain causes the request to be silently dropped by the client on Ascension, so deferring to the timer avoids that race
- Added `stuckTime` tracking: if `CountItemsAndMoney()` reports no change for more than 5 real seconds after a `TakeInboxItem` call, the current mail is skipped and processing continues with the next one (prevents permanent "In Progress" hangs)

**Open All — automatic mailbox pagination:**
- After exhausting the currently shown mails, `refreshFrame` now calls `CheckInbox()` and waits for the resulting `MAIL_INBOX_UPDATE` event before reading inbox counts; this avoids reading stale data that was a problem with the previous pure-timer approach
- Initial refresh delay reduced from 5 s to 2 s; an 8 s fallback timer fires a second `CheckInbox()` if `MAIL_INBOX_UPDATE` never arrives
- Once a full batch (50 mails or all remaining mail) is confirmed, Open All resumes automatically after 1 s

### Aux-addon (Post tab, Auctions tab & Tooltip)
**New feature — configurable history decay (`core/history.lua`, `core/slash.lua`):**
- Hardcoded `0.99` decay base replaced with a `get_decay()` / `set_decay(v)` pair backed by `aux.account.history_decay` SavedVariable; default changed to `0.75` (≈3-day half-life vs the original ~99-day half-life) so prices respond to market moves in days rather than months
- `/aux history decay <0.01–0.99>` slash command sets the decay live; `set_decay` flushes the value cache so the next price lookup recalculates immediately; current value shown in `/aux` help output
- `M.get_decay` exposed on the module so `slash.lua` can read it without a circular require

**New feature — `% Hist. Value` column in Auctions and Bids tabs (`gui/auction_listing.lua`):**
- Added sortable `% Hist. Value` column to both the Auctions tab and the Bids tab showing each listing's buyout (or bid) as a percentage of the Aux historical market value
- Reused the existing `record_percentage` / `percentage_historical` helpers already present in the file; no new logic needed
- Narrowed `High Bidder` (0.21→0.13), `Seller` (0.13→0.09), and `Status` (0.115→0.075) columns to make room without breaking total width

**Bug fix — tooltip crash "Invalid quest item in SetQuestLogItem" (`core/tooltip.lua`):**
- Hook wrapper called the original `SetQuestLogItem` (and all other hooked tooltip methods) unconditionally; when `LibExtraTip` called it with a stale/invalid quest item, the WoW API threw before returning, crashing the whole chain
- Fixed by wrapping the original call in `pcall` — on failure the error is caught silently and the custom `extend_tooltip` logic is skipped (correct, nothing valid to show); on success everything proceeds as before

**Bug fix — deposit always showing 1 silver (`tabs/post/core.lua`):**
- `unit_vendor_price()` works by temporarily slotting the item into the auction sell slot; in 3.3.5 this often returns `0` or fails silently, bypassing the `GetItemInfo` fallback (which only ran on `nil`, not `0`) and falling through to the `100 * stack_count` minimum
- Fixed by flipping priority: `GetItemInfo(item_id)` return value 11 (vendor sell price) is checked first since it is always reliable once the item is cached; the scanned `unit_vendor_price` is only used as a fallback when `GetItemInfo` returns nothing

**Bug fix — Buyout button never executing the bid:**
- `PlaceAuctionBid` must be called from a hardware event (button click), not from an `OnUpdate`/scan-thread callback; calling it from `on_auction` silently did nothing
- Replaced the old single-click flow with a two-click state machine (`idle → searching → found → idle`) in a `do`-block with private state (`buyout_state`, `buyout_index`, `buyout_price_total`)
- First click: validates selection, starts a list scan to locate the exact auction; sets state to `searching` and disables button
- On match found: stores auction index + total price, sets state to `found`, re-enables button with "click again to confirm" status
- Second click: IS the hardware event — safely calls `place_bid` and resets state to `idle`
- `reset_buyout_state()` called in `update_item()` to clear stale state when switching items

**Bug fix — Unit Starting Price showing inflated value after auto-selection:**
- Root cause: `bid_selection` was auto-selected to the cheapest bid row; `undercut()` with `stack=true` computes `ceil(unit_price × record.stack_size) / slider_stack_size`, producing e.g. 250g start price for a 5-stack at 50g/item when slider=1
- Fix: removed `bid_selection` auto-selection entirely from `update_auction_listing`; `bid_selection` is now only set when the user manually clicks a bid row
- Both start price and buyout price now derive from `buyout_selection` (same record, same stack size), so `unit_start_price ≤ unit_buyout_price` is always satisfied

**Bug fix — price_update running one frame before auto-selections were visible:**
- `price_update()` was called before `update_auction_listings()` in `on_update()`, so auto-selections from the current frame weren't yet in `buyout_selection` when prices were computed
- Fix: reordered `on_update()` — `update_auction_listings()` first, then `price_update()`

**New feature — manual price override:**
- Typing a custom price in the Unit Starting Price or Unit Buyout Price edit boxes was immediately overwritten on the next frame by the auto-selection logic
- Added `user_price_override` flag (private `do`-block with `get_user_price_override` / `set_user_price_override`)
- `char` handlers on both price inputs now set `user_price_override = true`; cleared on item switch (`update_item`) or explicit refresh (`refresh_entries`)
- `update_auction_listing` skips buyout auto-selection when `user_price_override` is true

**New feature — inventory list auto-scroll to selected item:**
- After posting or pressing Next, the newly selected item could be off-screen, requiring manual scrollbar use
- Added `M.scroll_to(item_listing, target_record)` to `gui/item_listing.lua`: finds item index, checks if already visible, and calls `scroll_frame:SetVerticalScroll(offset * ROW_HEIGHT)` only when needed
- `update_inventory_listing` wrapped in a `do`-block with `last_scroll_target` tracking; scrolls only when `selected_item` changes, preventing scroll disruption on same-item refreshes

**Bug fix — Auctions tab selection reset after cancelling an auction:**
- `CancelAuction()` fires `AUCTION_OWNED_LIST_UPDATE` → `scan_auctions()` → `wipe(auction_records)` → `SetDatabase(empty)` → `UpdateRowInfo()` calls `SetSelectedRecord(nil)`, destroying the selection before the rescan completes
- Fix in `tabs/auctions/core.lua`: save `prev_item_key` and `prev_name` from `listing.selected` before wiping; after `update_listing()` in `on_complete`, restore selection with three-tier fallback:
  1. Same `item_key` still has auctions → stay on it
  2. Item is gone → pick next item alphabetically by name
  3. Nothing after it → fall back to first remaining auction

**New feature — auto-advance to next item after posting:**
- After clicking Post, the callback now builds a sorted, filtered inventory list and selects the first item alphabetically after the one just posted
- Fallback chain: stay on same item if it still has quantity remaining → take the last item if nothing comes after alphabetically
- `select_next_item()` function added for the new **Next** button, with wrap-around (goes back to first item after the last)

**New feature — Next button:**
- New `Next` button in the Post tab toolbar advances to the next item in the inventory list (alphabetical order, wraps around)
- Enabled whenever inventory contains at least one auctionable item

**New feature — buyout auto-select lowest price:**
- After a scan completes, the buyout listing now automatically selects the first non-historical-value row (i.e. the lowest-priced real auction) so prices are immediately ready for undercutting without requiring a manual click
- Auto-selection is skipped if `user_price_override` is true (user has manually typed a price)

**Bug fix — deposit always showing 1s:**
- Deposit rate was 5%/25% — corrected to 15%/75% matching actual WoW 3.3.5 faction/neutral AH rates
- Duration dropdown stores enum integers (1/2/3), not hours; fixed by mapping DURATION_12/24/48 → 12/24/48 hours before computing `duration_factor = hours / 12`; previously dividing by 120 produced a near-zero multiplier that collapsed the deposit to the 1s minimum floor
- Deposit calculation now tries `select(11, GetItemInfo(item_id))` as primary vendor price source and falls back to `unit_vendor_price`; `GetAuctionSellItemInfo` is unreliable on Epoch

**Bug fix — default stack count now half of total quantity:**
- When selecting an item, stack size defaults to 1 and stack count defaults to `floor(total / 2)` (minimum 1), so half the bag quantity is queued by default instead of 1

### !!!ClassicAPI (game-shipped library)
**Bug fix — `SetAtlas` hard-error on unknown atlas name (`Util/SharedExtendedMethods.lua`):**
- `Method_SetAtlas()` called `Assert(Atlas, "SetAtlas: Atlas named X does not exist")` when a requested atlas wasn't in `ATLAS_INFO_STORAGE`; `Ascension_HelpUI` (a built-in game UI addon) requests `transmog-no-item` which only exists in retail — this caused a hard Lua error every time the Help menu was opened, crashing the entire layout generator
- Fixed by replacing the `Assert` with a silent `if not Atlas then return end` — the icon simply doesn't render instead of erroring; matches the expected graceful behaviour when an atlas is unavailable on the 3.3.5 client

### Whats-Training-Epoch
**Bug fix — "Now available at trainer" messages shown at level 60 (`Announce.lua`):**
- Login announcement and level-up announcement both fire at level 60 even though there are no more trainable levels beyond cap
- Added `UnitLevel("player") < 60` guard to the login delayed-announcement scheduler; added early `return` in the `PLAYER_LEVEL_UP` handler when new level ≥ 60
- `/wte test` command is unaffected and still works for manual testing

### TitanGoldTracker
- Uses `UIDropDownMenu_AddButton()` for context menus (not modern `MenuUtil`)
- Uses Ace3 timer wrappers (`ScheduleRepeatingTimer`, `CancelTimer`) — no `C_Timer` dependency
- Uses `hooksecurefunc()` for safe function hooking
- All frame templates are standard 3.3.5 Titan Panel templates
- **Cross-faction gold:** `GetTooltipText`, `FindGold`, and `TotalGold` now match all characters on the same realm regardless of faction; `server` key is now just the realm name and comparison uses `string.find(charserver, server, 1, true) == 1` to match any `Realm::Alliance` or `Realm::Horde` entry; tooltip header updated to show "All Factions"
