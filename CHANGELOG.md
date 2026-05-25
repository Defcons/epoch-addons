# Addon Changelog — Ascension (WoW 3.3.5a / Interface 30300)

All addons modified or created with Claude Code assistance for the Ascension private server.

---

## PEBGSync-3.3.5 v0.1 — New addon: cross-map BG teammate visibility *(2026-05-17)*
Battlegrounds on 3.3.5 freeze raid-frame data and (x,y) for teammates beyond the server's ~100-yard visibility range — the whole reason `UnitIsVisible(unit)` exists. This addon broadcasts each player's HP/MP/position over the addon channel so default UI raid frames, world map, and minimap have fresh data for teammates the server has stopped updating for.

Architecture (~1,300 lines across 8 files):

- **Observe-and-relay protocol** — each addon-user samples not just self but every visible raid member (`UnitIsVisible(unit) == true`) and broadcasts their state too. Coverage extends well past the addon-user fraction; even at 10-15% adoption you cover 50%+ of the raid. Conflict resolution: latest received wins, since all observers passed the visibility gate and have fresh first-hand data.
- **Tiered tick rates** — fast tier (HP, position, flags) every **0.5s**; slow tier (MP, class) every **2.0s**. Two-tier model amortises per-message overhead while keeping HP/position responsive enough to act on. Both well under 3.3.5's ~10 msg/sec outbound throttle.
- **Wire format**: pipe + comma + semicolon delimited, batched to fit 5-6 records per ~255-byte message. Per-mille (0-1000) x/y gives ~3.7 yard precision on a 1000-yard BG. Worst-case sender: ~500 bytes/sec; worst-case receiver (40-player AV, 30% adoption): ~6 KB/sec.
- **Flag-carrier detection** — scans for `Warsong Flag` / `Silverwing Flag` / `Alliance Flag` / `Horde Flag` / `Netherstorm Flag` auras; that bit travels in the per-record flag byte alongside in-combat / dead / ghost / mounted.
- **Default UI compatible** — non-invasive overlays only. Standalone movable HP/MP HUD frame (`UI/Roster.lua`), world map blips on `WorldMapDetailFrame` children, minimap blips clamped to a circle around the player. No raid-frame replacement; works alongside whatever frames the user has.
- **Opt-in enemy tracking** (`/pebg enemy on`, default off) — broadcasts enemies the local player can target/mouseover/raid-mark, approximated at the local player's coords (since nameplates don't carry world coords on 3.3.5). Separate `PEBGSync_E` prefix, separate cache, separate prune (15s vs 5s — enemy positions stale faster).
- **Slash commands**: `/pebg show|hide|toggle`, `on|off`, `enemy on|off`, `worldmap`, `minimap`, `status`, `help`.
- Auto-shows the roster HUD on BG entry, auto-hides on exit.

Files: `PEBGSync-3.3.5.toc` / `PEBGSync-3.3.5.lua` / `Core/{Const,Protocol,Engine,Enemy}.lua` / `UI/{Roster,WorldMap,Minimap}.lua`. Tracked in `.gitignore` exception list.

---

## unitscan v1.2 — Suppress ADDON_ACTION_BLOCKED spam on Ascension *(2026-05-10)*
unitscan probes for nearby units by repeatedly calling `TargetUnit(name)` and watching for `ADDON_ACTION_FORBIDDEN` (the protection event that signals the unit exists but can't be targeted from non-secure code). On retail 3.3.5 this fires the FORBIDDEN variant; on Ascension's server some calls fire `ADDON_ACTION_BLOCKED` instead — and unitscan was only listening for / suppressing FORBIDDEN, so:
- the addon's "found a unit" detection silently failed when the server emitted BLOCKED, and
- the default UI's red "AddOn 'unitscan' tried to call protected function 'TargetUnit()'" message leaked through (BugSack collected 29× in one session).

Three fixes in `unitscan.lua`:
1. **`unitscan.target()` now bails on `InCombatLockdown()`** as a belt-and-suspenders combat guard. `UPDATE()` already does this, but a state transition mid-frame could otherwise let one TargetUnit reach the protected path. Closes most of the loud combat-lockdown BLOCKED reports.
2. **OnEvent dispatcher now treats `ADDON_ACTION_BLOCKED` identically to `ADDON_ACTION_FORBIDDEN`** — sets the internal `forbidden` flag so unitscan's "found" detection works regardless of which variant Ascension emits.
3. **`UIParent:UnregisterEvent('ADDON_ACTION_BLOCKED')`** added next to the existing FORBIDDEN unregister, so the default-UI red error and the static popup are both suppressed for both events.

Note: BugSack/BugGrabber collect events on their own frame and may still log these. Configure their ignore filter for `ADDON_ACTION_BLOCKED` originating from `unitscan` if the BugSack count is still annoying.

TOC bump 1.0 → 1.2 (1.1 was a previously-unreleased internal version).

---

## EpogArmory v1.10.0 — Dungeon frame layout polish *(2026-05-25)*

Consolidated public release of v1.9.2 + v1.9.3 internal patches. Two UI fixes to the Dungeon Run frame from in-game screenshot feedback.

### Stale prompt fixed

The "Start /combatlog for this run? [Yes] [No]" prompt stayed visible even after logging was started by another means (bottom "Start logging" button, raid auto-log claiming an existing log, another addon turning `/combatlog` on). It overlapped the Bosses section and the `CombatLogQuickButtonFrame` quick controls.

Cause: the visibility gate only evaluated `not loggingActive` on the first eligible tick. Once `promptShown = true`, the only remaining hide trigger was `not currentDungeon` (leaving the dungeon).

Fix: recompute visibility every tick — `loggingActive` or `userDeclinedLog` now always trigger `Hide()` regardless of `promptShown`.

### Compact rows + dynamic layout

In LBRS (6 bosses + 7 trash buckets), the bottom "Stop logging" button clipped the last trash row, and BRD/UBRS (fewer bosses) had a big empty gap between the last boss and the trash header. Both caused by static layout reserving worst-case space for 10-boss multi-variant previews.

Two changes:

1. **Tighter rows.** Boss/trash pitch 11px → 10px.
2. **Dynamic layout.** Each `UpdateUI` tick repositions the trash label + rows to sit immediately below the actual last visible boss row (8px gap). Frame height is recomputed to fit visible content, lower-bounded at 270px so the header still fits on minimal rosters (e.g. Onyxia: 1 boss, 0 trash).

Per-dungeon visible-height impact (approximate):

| Dungeon | Before (fixed 430) | After (dynamic) |
|---|---|---|
| BRD (4+4) | 430, empty middle | ~318 |
| LBRS (6+7) | 430, button clipping last row | ~378 |
| UBRS (4+4) | 430 | ~318 |
| Scholomance (8+4) | 430 | ~338 |
| Stratholme combined preview (10+0) | 430 | ~318 |
| Stratholme Live (4+5) | 430 | ~328 |
| Onyxia's Lair (1+0) | 430 | 270 (clamped floor) |

`SetHeight` only fires when the delta is >1px so there's no per-tick flicker.

### Backward compatibility

- No SavedVariables changes.
- No wire-format / mesh-protocol impact.
- Mesh peers running v1.9.x will receive the auto-update notification pointing here.

### Files

Same five files as v1.9.1, with the dungeon module changes in `EpogArmoryDungeon.lua`. No new files.

---

## EpogArmory v1.9.3 — Dungeon frame: compact rows + dynamic layout (internal) *(2026-05-25)*

**Bug.** In LBRS (6 bosses + 7 trash buckets), the bottom "Stop logging" button clipped the last trash row ("Bloodaxe"). Two contributing issues:

1. Boss/trash row pitch was 11px — slightly too generous.
2. Trash section was anchored at a static y position reserved for the worst-case 10-boss preview. For dungeons with fewer bosses (LBRS = 6, BRD = 4, Scholo = 8), this left a big empty gap between the last boss and the trash header, pushing the trash rows down into the button area.

**Fix.** Two changes, both in `EpogArmoryDungeon.lua`:

1. **Tighter rows.** `BOSS_PITCH` and `TRASH_PITCH` 11 → 10.
2. **Dynamic layout.** Each `UpdateUI` tick now repositions the trash label + all trash rows to sit immediately below the last visible boss row (with an 8px section gap). Frame height is also recomputed to fit the actual visible content — no more empty space, no more bottom-button overlap. Lower-bounded at 270px so the header section always fits even on no-boss instances.

Constants exposed on the frame for the repositioner: `BOSS_LABEL_Y`, `BOSS_TOP`, `BOSS_PITCH`, `TRASH_PITCH`, `SECTION_GAP`, `LABEL_TO_ROW`, `FRAME_FOOTER`.

**Per-dungeon visual impact** (approximate visible heights):

| Dungeon | Before (fixed 430) | After (dynamic) |
|---|---|---|
| BRD (4 boss + 4 trash) | 430, big empty middle | ~318 |
| LBRS (6 + 7) | 430, button clipping | ~378 |
| UBRS (4 + 4) | 430 | ~318 |
| Scholomance (8 + 4) | 430 | ~338 |
| Stratholme combined preview (10 + 0) | 430 | ~318 |
| Stratholme Live (4 + 5) | 430 | ~328 |
| Onyxia's Lair (1 + 0) | 430 (manual-open only) | ~270 (min clamp) |

Frame uses `SetHeight` only if the delta is >1px to avoid per-tick flicker.

Patch-level. Rolls into the next public release with v1.9.2.

---

## EpogArmory v1.9.2 — Hide dungeon-frame /combatlog prompt when logging is active (internal) *(2026-05-25)*

**Bug.** Dungeon frame's "Start /combatlog for this run? [Yes] [No]" prompt stayed visible even after logging was started by another means (clicking the bottom "Start logging" button, raid auto-log claiming an existing log, another addon turning /combatlog on). Real reproduction: user in LBRS clicked the bottom Start-logging button → status changed to "Logging: ACTIVE" → prompt remained in the frame, overlapping the bosses section and the CombatLogQuickButtonFrame quick controls.

**Cause.** The visibility gate evaluated `not loggingActive` only on the first eligible tick (when `promptShown` was still false). Once `promptShown = true`, the elseif chain only re-hid the prompt when `not currentDungeon` — leaving the prompt stuck on screen for the rest of the run regardless of what logging did.

**Fix.** Rewrote the gate so the visible state is recomputed every tick:

```lua
if not currentDungeon then
    f.prompt:Hide()
elseif loggingActive or userDeclinedLog then
    f.prompt:Hide()    -- new: hide unconditionally when prompt is moot
elseif not promptShown then
    f.prompt:Show()
    promptShown = true
end
```

Hides immediately on any transition to `loggingActive == true`, regardless of `promptShown`. The flag still suppresses re-asking during a normal "prompt → user dismissed → prompt stays hidden" flow.

Patch-level — no public release, mesh auto-update notification stays silent. Will roll into the next minor.

---

## EpogArmory v1.9.1 — Single-target dummy enforcement + whisper-spam fix *(2026-05-21)*

Consolidated public release of the v1.9.0 + v1.9.1 internal patches. Two themes: dummy parses are now Project-Epoch-realm-enforced single-target only (matches epoglogs server-side rule introduced in v0.86.6), and a long-running chat-spam bug in the mesh code is fixed.

### Single-Target-Only dummy enforcement

`epoglogs.com` v0.86.6+ rejects combat-log uploads where the player damaged 2+ training dummies in one pull. The leaderboards at `epoglogs.com/dummy-stats` are single-target only — Expert's (L60) vs Heroic (L63) dummies have very different EHP curves and AoE rotations would pollute the rankings. The addon now mirrors that rule locally so users find out *before* they upload.

**Detection** (`EpogArmoryDummy.lua`):
- Per-fight set `aoeExtraDummyGUIDs` tracks distinct dummies that aren't the primary `savedDummyGUID`. Populated from the CLEU handler whenever `destName` matches the `Training Dummy` substring pattern. Reset in both `DoStartLogging` and `DoStartPractice` alongside the other per-fight state.
- Mirrors the server-side parser regex `/\bTraining Dummy\b/` on destName — substring match agrees in practice (no real-world non-dummy NPC has the phrase as a substring).

**Realm gating** via `DEFAULT_SKIP_AOE_REALMS` (`Project Epoch` / `Epoch` / `ProjectEpoch`). Override list in `EpogArmoryDB.skipAoERealms` for any exact-string mismatch. CoA-style realms where AoE training is valid content keep the save but tag the fight with `aoe=true` so offline analytics can distinguish.

**Realtime visible feedback:**
- Dummy frame title now reads `EpogLogs . Dummy Parse . Single-Target Only` (the trailing tag is grey via `|c` escape — quiet subtitle, doesn't fight with the main title).
- New `f.aoeWarnLabel` under the state badge: hidden by default, shown as `Multi-target damage detected — fight invalidated` (red) the moment a second dummy GUID appears in CLEU.
- `validThroughout` flips false on first extra-dummy detection so the verdict at end-of-fight matches what `SaveFightRecord` does — no "showed CLEAN locally but rejected on upload" surprise.

**SaveFightRecord behavior table:**

| extraDummyCount | Realm in skip-list | Action |
|---|---|---|
| 0 (single dummy) | n/a | Save normally |
| >0 | Yes (PE) | Skip the save entirely. Show `EPOGARMORY_AOE_DUMMY_REJECTED` popup + red chat line |
| >0 | No (CoA-style) | Save with `aoe=true`, `aoeExtraDummyCount`, `aoeExtraDummyName` tagged on the record |

### Fix: "No player named X" whisper-spam bug

**Bug.** Multiple lines of `No player named 'X' is currently playing.` system errors flooding chat when a peer that the addon was syncing TO logged off mid-burst.

**Root cause.** `SendAddonMessage(PREFIX, body, "WHISPER", target)` to an offline player triggers that exact system error on Project Epoch (and other 3.3.5 forks). The sync-response path queues up to `SYNC_MAX_SETS_PER_RESPONSE` (200) WHISPER chunks back to the requester. If the requester logs off mid-burst, every remaining queued chunk pops one at a time and fires the error — **up to 200 spam lines per bad-luck sync request**.

**Fix.** Two new helpers in `EpogArmory.lua` + a guard at the send site:

1. **`IsCharOnline(name)`** — TTL-cached (2s) wrapper over `BuildAutoSyncReachable()`. Cheap per-tick check that doesn't re-walk the guild roster every `BROADCAST_STAGGER` (0.5s).
2. **`DrainWhispersTo(targetName)`** — walks `outQueue` and removes all queued items with `ch == "WHISPER"` and `target == targetName`. Called once when we detect a WHISPER target went offline, so we don't pop+error the remaining 199 chunks one at a time.
3. **Guard at the SendAddonMessage call site** in the OnUpdate driver: if the item is a WHISPER with an offline target, drop + drain. Otherwise normal send. Drop count logged via `dprint`.

**No behavior change** for online targets, party/raid/guild broadcasts (`PARTY`/`RAID`/`GUILD`/`BATTLEGROUND` ignore the target arg entirely), or any non-WHISPER path. Pure offline-target guard.

### Backward compatibility

- New SavedVariables fields are additive: `EpogArmoryDB.dummyFights[].aoe`, `.aoeExtraDummyCount`, `.aoeExtraDummyName` (only set on AoE-tagged records).
- `EpogArmoryDB.skipAoERealms` is optional override; absent means use `DEFAULT_SKIP_AOE_REALMS`.
- Wire format unchanged — no mesh-protocol impact. Mixed-version meshes work fine.
- v1.8.x mesh peers will receive the auto-update notification pointing here.

### Files

Same five files as v1.8.0 — no new files added. `EpogArmoryDummy.lua` carries the AoE detection logic, `EpogArmory.lua` carries the whisper guard.

---

## EpogArmory v1.8.0 — Dungeon speedruns + raid auto-log + dummy practice mode *(2026-05-21)*

Consolidated public release of the v1.7.1–v1.7.11 internal iteration. Headline features: a new Dungeon Run frame tracking boss kills + trash buckets for the epoglogs leaderboard, raid auto-log with ownership management, a PRACTICE mode on the dummy frame for log-free DPS readouts, and polish on the existing dummy parse flow.

**Dungeon speedrun status frame** (new file `EpogArmoryDungeon.lua`)

Auto-opens when the player enters a tracked dungeon (`/epogarmory dungeon` to toggle manually). Shows:
- Dungeon name + variant selector buttons for multi-variant instances
- Live boss-kill progress with per-boss "(M:SS)" kill timestamps
- Trash bucket roster from the epoglogs leaderboard rules (e.g. `16/16 Scarshield`) with red/yellow/green color cues
- /combatlog status row (`ACTIVE` / `OFF`) + manual Start/Stop button
- Run timer tied to the actual logging session (stops when logging stops)
- One-time Yes/No prompt on entry asking whether to start /combatlog

**Tracked dungeons (8):**

| Dungeon | Bosses | Trash buckets |
|---|---|---|
| Blackrock Depths | 4 | 4 |
| Blackrock Spire — LBRS | 6 | 7 |
| Blackrock Spire — UBRS | 4 | 4 |
| Scholomance | 8 | 4 |
| Stratholme — Live | 4 | 5 |
| Stratholme — Undead | 6 | 6 |
| Baradin Hold | 4 | 6 |
| Onyxia's Lair *(raid)* | 1 | — |

**Multi-variant detection.** Blackrock Spire and Stratholme both have one instance name covering two leaderboard dungeons. Variant selector buttons appear on entry; first boss kill also auto-resolves the variant. Generic `variants` field in the data table so future multi-variant dungeons inherit the behavior automatically.

**Trash bucket display names are auto-derived** from the longest common word-prefix across each bucket's mob list (`{"Scarshield Legionnaire","Scarshield Acolyte",...}` → `Scarshield`). Manual `name` field is only used as a fallback for mob lists with no shared prefix (e.g. `Wailing Banshee / Shrieking Banshee` → manual `Banshees`). Collisions auto-disambiguate with `(1)`/`(2)` suffixes.

**Raid auto-log.** Entering a `"raid"` instance type (Onyxia's Lair currently) starts `/combatlog` automatically in the background with **no UI interruption** — frame stays hidden, no visible timer. Critical safety:

- Checks `LoggingCombat()` first — if another addon already started a log, we don't claim ownership and won't stop it on exit.
- Stops the log automatically when the player leaves the raid instance (only if we started it).
- Ownership flag persisted to SavedVariables so `/reload` during a raid doesn't lose the claim.
- New slash: `/epogarmory raidlog [on|off|status]` to toggle the auto-log preference (default on).

Highlighted multi-line chat block announces START / RESUMED / STOPPED transitions so the user always knows what's happening with the log.

**Dummy parse improvements**

- **PRACTICE mode** (cyan badge): when attacking a Training Dummy without auto-log enabled, the frame becomes a free DPS meter — tracks DPS / total damage / timer / auras, no file written, no 1:30 limit, no Validate button. The state badge is cyan instead of green so it's unmistakably different from a real log.
- **10-second strict validate window** with live countdown on the button label (`VALIDATE (10)` → `VALIDATE (1)`). Window expiry shows `LOG FAILED - click Reset to try again`.
- **Basic Campfire fallback marker** chained after Fishing in the validate macro. Covers the edge case where a player has a Fishing Pole equipped (Fishing would succeed instead of failing). Both spells write a `SPELL_CAST_FAILED` CLEU line — the site accepts either.
- **`/epogarmory testvalidate`** slash: jump straight into the validate-button state to exercise the marker round-trip without doing a full 1:30 parse. Useful for verifying the secure-button mechanism after client updates.

**Minimap menu**

Two new entries in the right-click context menu so users don't need to memorize slash commands:
- Open Dummy parse
- Open Dungeon run

**Slash commands added in this release:**

```
/epogarmory dummy           — toggle the Dummy parse frame
/epogarmory dungeon         — toggle the Dungeon run frame
/epogarmory testvalidate    — exercise the marker mechanism without a full parse
/epogarmory raidlog [on|off|status] — toggle raid auto-log
/epogarmory dungeondebug    — dump dungeon-detection diagnostic info
```

**Backward compatibility**

- All new SavedVariables fields are additive: `EpogArmoryDB.config.dummyAutoLog`, `EpogArmoryDB.config.raidAutoLog`, `EpogArmoryDB.dummyFights[]`, `EpogArmoryDB.session.addonStartedLog`.
- Wire format unchanged (no mesh-protocol impact).
- Mixed-version meshes work — older clients see no behavior change.
- v1.7.x mesh peers will receive the auto-update notification pointing here.

**Files added:**

- `EpogArmoryDummy.lua` (already shipped in v1.7.0; now v1.8.0 includes the v1.7.1+ improvements)
- `EpogArmoryDungeon.lua` (NEW in v1.8.0 — dungeon frame, ~970 lines)

---

## EpogArmory v1.7.11 — Raid auto-log: ownership check + auto-stop on exit + highlighted chat (internal) *(2026-05-21)*

Three improvements to the v1.7.7 raid auto-log feature, all from user feedback.

**1. Highlighted chat message.** The single one-liner is replaced with a multi-line framed block so it's hard to miss when raids start their auto-log:

```
=======================================
EpogArmory RAID AUTO-LOG STARTED
  Instance: Onyxia's Lair
  Log file: Logs/2026-05-21-HH.MM.SS WoWCombatLog.txt
  Will auto-stop when you leave the raid.
  /epogarmory raidlog off  to disable for future raids
=======================================
```

Three message variants based on detected state:
- `RAID AUTO-LOG STARTED` (green) — we started a new log
- `RAID AUTO-LOG RESUMED` (green) — log was already running and we own it (claim restored from SavedVariables after /reload)
- `raid detected` (subdued) — log was already running BUT we don't own it (another addon or user started it); we leave it alone and won't stop it on exit

**2. Don't fight other addons.** Before calling `LoggingCombat(true)`, check the current state via `LoggingCombat()` with no args (returns boolean — wrapped in `pcall` for safety on private-server forks that might change the API). If already on, the addon does NOT claim ownership, so it won't stop someone else's log on raid exit.

New helper:
```lua
local function IsLoggingActive()
    if not LoggingCombat then return false end
    local ok, isOn = pcall(LoggingCombat)
    if ok and type(isOn) == "boolean" then return isOn end
    return false
end
```

**3. Auto-stop on raid exit.** New module state:
- `addonStartedLog` — boolean. True if WE started the current `/combatlog` session (so we know to stop it on exit). False if someone else started it (we leave it alone).
- `wasInRaid` — boolean. Tracks whether the previous zone change had us in a raid. Used to detect "left a raid" transitions in the event handler.

The event handler now has a pre-detection block:

```
on PLAYER_LOGIN / PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA:
   1. compute currentInstanceType via IsInInstance()
   2. if wasInRaid AND not nowInRaid AND addonStartedLog:
        LoggingCombat(false)
        clear addonStartedLog + persist
        print STOP chat block
   3. wasInRaid = nowInRaid
   4. (then) DetectDungeon → OnEnterDungeon for the new instance (if any)
```

Stop chat block:

```
=======================================
EpogArmory RAID AUTO-LOG STOPPED
  Left raid instance - /combatlog closed.
=======================================
```

**Persistence across /reload.** `addonStartedLog` is saved to `EpogArmoryDB.session.addonStartedLog`. Restored at `PLAYER_LOGIN` with a sanity check: if the SV flag is true but `IsLoggingActive()` returns false (e.g. the log got stopped by something else between sessions), the flag is cleared.

This handles the /reload-during-raid case correctly:
1. User in raid, we started the log, `addonStartedLog = true` in SV
2. `/reload` happens
3. PLAYER_LOGIN restores `addonStartedLog = true`
4. PLAYER_ENTERING_WORLD detects we're still in a raid
5. OnEnterDungeon raid path sees `IsLoggingActive() == true` AND `addonStartedLog == true` → prints "RAID AUTO-LOG RESUMED" instead of starting a new log or treating it as foreign

Without this, we'd lose ownership on every /reload and never stop on exit.

**Edge cases verified:**

| Scenario | Behavior |
|---|---|
| Enter raid, no other addon logging | Start log, claim, print STARTED |
| Enter raid, another addon already logging | Don't start, don't claim, print "(not ours, leaving alone)", won't stop on exit |
| Enter raid, /reload, still in raid | Restore claim from SV, print RESUMED, log continues |
| Exit raid (we own log) | Stop log, clear claim, print STOPPED |
| Exit raid (we don't own log) | Do nothing — print nothing |
| Exit raid into 5-man (we own log) | Stop log first, THEN normal 5-man flow with Yes/No prompt |
| Raid auto-log toggle OFF, then enter raid | No auto-log fires, no claim |

**Site-side impact:** none. Pure addon-side ownership management.

**No backward-compat risk.** Existing users will get the better chat message on next raid entry. Users who already had their own /combatlog logic via another addon will benefit from the ownership check.

Patch-level. Rolls into v1.8.0 with v1.7.1–v1.7.10.

---

## EpogArmory v1.7.10 — Dummy PRACTICE mode (DPS meter without log) (internal) *(2026-05-21)*

When you attack a Training Dummy in a city without having opted into logging (`config.dummyAutoLog == false`, which is the default), the dummy frame now enters a new **PRACTICE** state — tracks DPS + total damage + timer + auras, but does NOT call `LoggingCombat(true)`. No file is written, no marker, no 1:30 limit. Just a free DPS readout while you practice your rotation.

**State machine extended:**

```
idle ──(combat with dummy, auto-log ON)──▶ logging ──...
idle ──(combat with dummy, auto-log OFF)──▶ practice ──(combat ends)──▶ stopped (wasPractice=true)
                                          ──(Stop click)──▶ stopped (wasPractice=true)
stopped ──(Reset)──▶ idle
```

**New function `DoStartPractice()`** mirrors `DoStartLogging()` but skips `LoggingCombat` and never sets `logFilename`. State machine, fight-start-time, damage counter, and aura listings are otherwise identical to the real-logging path.

**UI changes:**

- New state badge: **`PRACTICE`** in cyan (`r=0.3, g=0.85, b=1`) — clearly differentiated from green `LOGGING` so users can never confuse "I have a real log" with "this is practice".
- Timer format: `M:SS` (no `/ 1:30` target) since there's no fixed limit. Counts up freely while you're swinging at the dummy.
- Progress bar: cyan instead of green/yellow. Grows over the 1:30 reference and caps so the bar visual remains useful as a "how long have I been at this" indicator without needing extra UI.
- DPS readout: same big focal `<num> DPS` as logging mode.
- Total damage subtitle: `<num> damage (practice)` — the suffix makes it unambiguous.
- Action button: `Stop` (cancels practice, transitions to stopped).
- Validate button: never shown in practice (no marker to emit).
- Verdict line in `stopped` state for practice: `Practice complete - no log file written` (cyan). Distinct from the CLEAN / INVALID / LOG FAILED verdicts of real logs.

**CLEU damage tracking** now activates in `practice` as well as `logging` / `stopping` — same SWING/SPELL/RANGE damage event parsing fills `fightTotalDamage`.

**OnTick** branches: when state is `practice`, runs `ValidateNow()` (just to keep the aura listings fresh — doesn't flip any validation flag) and refreshes UI. No 1:30 marker transition, no idle-stop, no hard timeout.

**`OnLeaveCombat`** branches: when state is `practice`, sets `wasPractice = true` and transitions to `stopped`. No `LoggingCombat(false)` call (it was never started).

**Action button OnClick** in `practice` state: same as the `Stop` semantic in `logging`/`stopping` — flip to `stopped` with `wasPractice = true`.

**`wasPractice` flag** is set in 4 places (`DoStartPractice` → false, practice→stopped transitions → true, Reset from stopped → false, `DoStartLogging` → false for defensive cleanup) so a stale practice flag can never leak into a real log session's verdict rendering.

**No backward-compat risk.** Real logging path (auto-log on, manual Ready) is unchanged. Existing users who haven't enabled `dummyAutoLog` will see the new PRACTICE state appear next time they attack a dummy — that's the intended UX upgrade. Site-side gating contract is unaffected (practice writes no file).

Patch-level. Rolls into v1.8.0 with v1.7.1–v1.7.9.

---

## EpogArmory v1.7.9 — Minimap menu: Dummy parse + Dungeon run entries (internal) *(2026-05-20)*

Two new items in the minimap right-click menu so users don't need to remember the slash commands:

```
EpogArmory
  Open Armory
  Open Dummy parse    ← v1.7.9
  Open Dungeon run    ← v1.7.9
  Status
  Toggle Debug
  Help
  Wipe DB
  Cancel
```

**Implementation.** New `add()` calls in `InitMinimapMenu` (`EpogArmoryUI.lua` ~line 2540). Each clicks the relevant module's `_G.EpogArmory*_Toggle` function with a defensive fall-through to `SlashCmdList["EPOGARMORY"]("dummy" / "dungeon")` if the module global isn't loaded (e.g. a Lua error halted the dungeon module file). Same idempotency as the slash commands — clicking again closes the frame.

**Tooltip updated** to mention the new menu entries:

```
Right-click: menu (Dummy/Dungeon, status, debug, wipe...)
```

No state changes, no SavedVariables. Pure UX shortcut.

Patch-level. Rolls into v1.8.0 with v1.7.1–v1.7.8.

---

## EpogArmory v1.7.8 — Raid silent mode (background logging, no UI) (internal) *(2026-05-20)*

Per user feedback on v1.7.7: raid entry should run `/combatlog` invisibly. The dungeon frame should NOT auto-open, and the visible timer should NOT start. The chat confirmation is the only sign anything happened.

**Branch split in `OnEnterDungeon`:**

| Instance type | Behavior on entry |
|---|---|
| `"raid"` + `raidAutoLog == true` | `LoggingCombat(true)` + chat message + frame stays hidden. No timer. |
| `"raid"` + `raidAutoLog == false` | Falls through to 5-man path (frame opens, Yes/No prompt). |
| `"party"` | Original behavior — frame opens, Yes/No prompt. |

**State set in raid silent mode:**
- `currentDungeon = "Onyxia's Lair"` (so re-entries on /reload don't double-trigger the chat message via the `currentDungeon == dungeonKey` guard)
- `dungeonStartTime = GetTime()` (boss kill CLEU still records "+ Onyxia (M:SS)" relative to entry — useful if user later opens the frame manually)
- `loggingActive = true` (so the StopLogging button in a manually-opened frame works correctly)
- `promptShown = true` (suppresses the Yes/No prompt if the frame is opened manually)
- **NOT set:** `logStartTime` — this is what the frame timer watches. Stays `nil` so the timer reads `--:--`.

**Frame behavior:**
- Auto-open: suppressed for raids.
- `/epogarmory dungeon` toggle: still works, opens frame on demand.
- Frame contents when manually opened during raid:
  - Dungeon name: "Onyxia's Lair"
  - Timer: `--:--` (grey, as designed)
  - Status: `IN PROGRESS (0 / 1 bosses)` then `COMPLETE` after kill
  - Logging row: `Logging: ACTIVE` (green)
  - Boss list: `- Onyxia` then `+ Onyxia (M:SS)` after kill
  - Bottom button: `Stop logging` (functional)

**Edge cases:**
- User comes from a 5-man (frame visible) → zones to Onyxia: frame is **hidden** on entry (via `frame:Hide()`), 5-man state is reset by `ResetRun()`.
- User /reloads inside Onyxia: `currentDungeon` is `nil` after reload → `OnEnterDungeon` runs → raid path → chat message + log restart (idempotent on WoW side).
- User wipes + runs back without zoning out: `currentDungeon == dungeonKey` guard prevents re-trigger.
- User wipes + zones out + back in: counts as fresh entry. Auto-starts a new log file.

**`raidAutoLog` config toggle unchanged.** `/epogarmory raidlog [on|off|status]` still controls the behavior. When off, raid entry falls through to the 5-man Yes/No prompt path.

Patch-level. Rolls into v1.8.0 with v1.7.1–v1.7.7.

---

## EpogArmory v1.7.7 — Raid auto-log + Onyxia's Lair support (internal) *(2026-05-20)*

Adds Onyxia's Lair to the dungeon-frame's tracked instances and introduces raid-specific auto-start behavior for `/combatlog`.

**Onyxia's Lair entry.** Single boss roster, no trash bucket tracking (whelps come in scripted waves rather than as countable adds). `GetInstanceInfo()` is expected to return `"Onyxia's Lair"` — if Epoch returns a different name we'll patch the key with `/epogarmory dungeondebug` in-instance.

```lua
["Onyxia's Lair"] = {
    displayName = "Onyxia's Lair",
    bosses = { "Onyxia" },
},
```

**Raid auto-log.** When entering a `"raid"` instance type (per `IsInInstance()`), the dungeon module now skips the Yes/No prompt and calls `StartLogging()` immediately. Rationale: raids are the long, fight-heavy content that benefits most from automatic logging; the prompt adds friction. 5-man dungeons (`"party"` instance type) keep their Yes/No prompt behavior unchanged.

Detection logic in `OnEnterDungeon`:
- Calls `IsInInstance()` to get the current instance type
- If type is `"raid"` AND `EpogArmoryDB.config.raidAutoLog == true` AND not already logging
- → call `StartLogging()`, set `promptShown = true` to suppress the Yes/No prompt
- → chat message: "raid detected ([name]) - auto-started /combatlog. Toggle via /epogarmory raidlog."

**Config.** New SavedVariable: `EpogArmoryDB.config.raidAutoLog` (boolean, default `true`). Initialized at `PLAYER_LOGIN` only if absent — existing users who explicitly set it to `false` keep their preference.

**Slash command.** `/epogarmory raidlog [on|off|status]` — toggle or inspect the raid auto-log preference. Status output explains current behavior; on/off persists immediately to SavedVariables.

```
/epogarmory raidlog status
> EpogArmory raidlog: ON
>   When ON, /combatlog starts automatically the moment you enter a raid instance (currently: Onyxia's Lair).
>   Toggle: /epogarmory raidlog on  |  /epogarmory raidlog off
```

**Edge cases handled:**
- Already logging on entry (e.g. user manually started /combatlog): auto-start skipped (idempotency)
- Multiple raid entries in one session: each entry resets `logStartTime`/`logEndTime` via `StartLogging()`, producing a fresh log file each time
- `/reload` while in a raid: auto-start fires again on `PLAYER_ENTERING_WORLD` — `LoggingCombat(true)` is idempotent on the WoW side so the existing log file isn't disrupted, but the addon's internal `logStartTime` resets to "now" (cosmetic only; the actual log file content is unaffected)

**Multi-raid forward-compat.** The auto-log branch keys off the instance type, not the dungeon name. When more raids get added (Molten Core, BWL, etc.), they'll inherit auto-log behavior automatically as long as they're listed in `DUNGEONS`.

Patch-level. Rolls into v1.8.0 with v1.7.1–v1.7.6.

---

## EpogArmory v1.7.6 — Auto-truncated trash bucket names (internal) *(2026-05-20)*

Per user request: when a trash bucket's mob list is a "big OR formula with all same first name", derive the display name from the common word-prefix instead of hand-curating it.

**Implementation: `ComputeBucketName(bucket)`.** Splits each mob name into words, walks word-by-word across all mobs in the bucket finding the longest common prefix. If the prefix is non-empty, that's the display name. If no common prefix exists (e.g. Strat's `{"Wailing Banshee","Shrieking Banshee"}` shares "Banshee" as a suffix but not prefix), falls back to the manual `name` field, or finally `mobs[1] .. " ..."`.

Examples:

| Bucket mobs | Auto display name |
|---|---|
| `{"Scarshield Legionnaire","Scarshield Acolyte","Scarshield Spellbinder","Scarshield Raider","Scarshield Warlock"}` | `Scarshield` |
| `{"Anvilrage Footman","Anvilrage Guardsman"}` | `Anvilrage` |
| `{"Rage Talon Dragon Guard","Rage Talon Fire Tongue","Rage Talon Captain"}` | `Rage Talon` |
| `{"Fireguard"}` (single mob) | `Fireguard` |
| `{"Wailing Banshee","Shrieking Banshee"}` (no common prefix) | falls back to manual `"Banshees"` |

**Collision auto-disambiguation.** After computing names, scans each trash list for duplicates. Same-named buckets get suffixed `" (1)"` / `" (2)"`. Example: LBRS's two Smolderthorn buckets both auto-compute to `"Smolderthorn"`; load-time post-processing makes them `"Smolderthorn (1)"` / `"Smolderthorn (2)"`.

**Data cleanup.** Dropped the manual `name` field from buckets where auto would give the same result (BRD all 4, LBRS 5 of 7, UBRS 2 of 4, Scholo 1 of 4, Strat Live 2 of 5, Strat Undead 3 of 6, Baradin Hold 3 of 6). Manual `name` retained where:
- Mobs share no common word-prefix and the manual label provides a semantic group name (e.g. Strat `"Skeletons/Cadavers"`, Scholo `"Spectral / Acolyte"`)
- Two buckets would otherwise collide AND the semantic split is more useful than the numeric `(1)/(2)` suffix (e.g. Strat Live `"Crimson melee"` / `"Crimson caster"`, Baradin Hold `"Blackstone melee/crew/elite"`)

**No site-side change.** The bucket names are purely an in-game display label — the leaderboard parser only cares about the underlying mob names + kill counts, which are unchanged.

Patch-level. Rolls into v1.8.0 with v1.7.1–v1.7.5.

---

## EpogArmory v1.7.5 — Dungeon: trash buckets + log-tied timer + compact + kill timestamps (internal) *(2026-05-20)*

Four interlocking improvements to the dungeon frame from in-game feedback.

**1. Trash bucket tracking.** Each dungeon now ships with its full trash bucket roster from the epoglogs leaderboard rules: a list of mob-name groups with required kill counts. Rendered as a new section below the boss list:

```
Trash (3 / 7 buckets)
  16/16 Scarshield
   6/6  Spirestone
   8/10 Smolderthorn A
   0/9  Smolderthorn B
   ...
```

Color cues per row: red = 0 kills, yellow = partial, green = met requirement. Trash header shows aggregate `(N / M buckets complete)`. For multi-variant dungeons, the trash section shows `(pick variant first)` until the variant is selected/resolved since buckets are per-variant.

Implementation: `TRASH_LOOKUP[dungeonKey][variantKey or "_"][mobName] = bucketIndex` built once at load time. CLEU `UNIT_DIED` increments `trashKills[bucketIdx]`. Trash counters reset on dungeon entry AND on variant selection/auto-resolve (since LBRS buckets ≠ UBRS buckets — indices don't transfer).

Trash bucket data added for all 7 dungeons (4-7 buckets each, totals: BRD 4, LBRS 7, UBRS 4, Scholo 4, Strat Live 5, Strat Undead 6, Baradin Hold 6). Bucket names kept short ("Anvilrage", "Scarshield", "Crimson melee") so rows fit in 244px of width.

**2. Timer tied to logging, not dungeon entry.** Per user feedback: the timer was running off `dungeonStartTime` and counted forever, even after logging was stopped. Now driven by `logStartTime` / `logEndTime`:

| State | Timer shows |
|---|---|
| Logging active | live count from `logStartTime` |
| Logging stopped (post-Start) | frozen at `logEndTime - logStartTime`, yellow tint |
| Never started | `--:--`, grey |

`StartLogging` sets `logStartTime` + clears `logEndTime`. `StopLogging` sets `logEndTime`. Restarting the log resets `logStartTime` (since each log file is its own session — the leaderboard sees the most recent file).

**3. Boss kill timestamps.** When a boss dies, the elapsed time since dungeon entry is stored in `bossKillTimes[bossName]`. The boss row in the UI appends `(M:SS)` after the boss name:

```
+ Lord Incendius (1:34)
+ Magmus (3:22)
- Emperor Dagran Thaurissan
- Princess Moira Bronzebeard
```

Note timestamps are relative to **dungeon entry**, not log start. Boss kill events fire whether or not logging is on — relative-to-entry gives consistent timestamps regardless of when the user started/stopped /combatlog.

Internally the `bossKills` set-of-booleans was replaced by `bossKillTimes` set-of-numbers. All previous `if bossKills[name]` truthiness checks still work since a stored number is truthy.

**4. Compact layout.** Multiple sizing changes per user feedback ("Make it generally more compact"):

| Element | Before | After |
|---|---|---|
| Timer font | `GameFontNormalHuge` (~32pt) | `GameFontNormalLarge` (~16pt) |
| Status badge font | `GameFontNormal` | `GameFontHighlightSmall` |
| Prompt frame height | 54px | 38px |
| Prompt buttons | 80×22 | 70×18 |
| Boss row pitch | 12px | 11px |
| Boss row slot count | 12 (preallocated) | 10 (combined preview cap) |
| Frame total height | 432 | 430 (smaller total despite added trash section) |

Boss section starts higher (TOPLEFT y=-192) thanks to the smaller timer. Trash section fits below in the freed space (TOPLEFT y=-310). Bottom button position unchanged (`BOTTOM` offset 14).

**No site-side impact.** All these are purely in-game UX. The combat log gating contract is unchanged.

Patch-level. Rolls into v1.8.0 alongside v1.7.1–v1.7.4.

---

## EpogArmory v1.7.4 — Dungeon multi-variant fix (BRS/Stratholme) (internal) *(2026-05-20)*

Fixes the v1.7.3 dungeon frame failing to detect when in Blackrock Spire. Root cause: `GetInstanceInfo()` returns **`"Blackrock Spire"`** as the instance name regardless of whether the player is doing LBRS or UBRS (both sides share one instance on 3.3.5). My DUNGEONS table keyed on `"Lower Blackrock Spire"` / `"Upper Blackrock Spire"` which the client never returns — so the lookup silently fell through and the frame never opened.

Same issue would have hit Stratholme on a fresh run (one instance name, two leaderboard variants). It was masked there only because the v1.7.3 code had Stratholme-specific side-detection logic; BRS got nothing.

**Refactor: generic multi-variant support.** The `sides` field on the Stratholme entry is now generalized to `variants` and applied to any multi-variant dungeon. The data shape:

```lua
["Blackrock Spire"] = {
    variants = {
        lbrs = { displayName = "Lower Blackrock Spire", shortName = "LBRS", bosses = {...} },
        ubrs = { displayName = "Upper Blackrock Spire", shortName = "UBRS", bosses = {...} },
    },
},
["Stratholme"] = {
    variants = {
        live   = { displayName = "Stratholme — Live",   shortName = "Live",   bosses = {...} },
        undead = { displayName = "Stratholme — Undead", shortName = "Undead", bosses = {...} },
    },
},
```

`BOSS_TO_VARIANT[dungeonKey][bossName] = variantKey` is generated once at file load for O(1) auto-resolution on first boss kill.

**Variant selection buttons (per user request).** A new `variantContainer` row in the frame between the dungeon name and the timer, holds 2 buttons side-by-side (`LBRS` / `UBRS` or `Live` / `Undead`). Shown only when the current dungeon has variants AND no variant is yet resolved. Click → variant locks in → frame redraws showing only that variant's roster. Auto-resolution by first boss kill still works as a fallback — useful when the user forgets to click before pulling.

**Layout impact:** frame height bumped 400 → 432, timer/status/prompt/bosses rows all shifted down 32px to make room for the variant button row. Boss row max stays at 12 slots (highest variant has 6 bosses; combined pre-resolution preview = 10).

**Renames** in module state: `stratSide` → `currentVariant` (per-dungeon variant key). No external API change — the slash command surface is the same. The site-side gating contract is also unchanged.

**Verified behavior in v1.7.4:**

| Instance | Frame shows | First boss kill action |
|---|---|---|
| Blackrock Depths | "Blackrock Depths" header, 4 bosses | Records kill |
| Blackrock Spire | "Blackrock Spire (variant: select below)" + [LBRS] [UBRS] buttons + all 10 bosses tagged | Auto-resolves to LBRS or UBRS if user hadn't clicked |
| Scholomance | "Scholomance" header, 8 bosses | Records kill |
| Stratholme | "Stratholme (variant: select below)" + [Live] [Undead] buttons + all 10 bosses tagged | Auto-resolves on first side-specific kill |
| Baradin Hold | "Baradin Hold" header, 4 bosses | Records kill |

Patch-level; rolls into v1.8.0 alongside v1.7.1–v1.7.3.

---

## EpogArmory v1.7.3 — Dungeon speedrun status frame (internal) *(2026-05-20)*

New module `EpogArmoryDungeon.lua` — companion to the existing dummy-parse frame, but for dungeon speedrun runs that feed the epoglogs.com leaderboard. Auto-opens when the player enters a tracked dungeon; shows live boss-kill progress + run timer + `/combatlog` status; prompts once on entry to start the log.

**Passive validation model.** Unlike the dummy frame's secure-button marker, dungeon runs don't need a marker — the combination of zone match + boss `UNIT_DIED` events in the log IS the validation. The site parses the file for the expected boss kill sequence. No Validate button, no Fishing/Basic Campfire macro, just passive observation. Matches how Warcraftlogs treats raid logs.

**Tracked dungeons** (7) — sourced from the epoglogs.com leaderboard parsing rules pasted 2026-05-20:

| Dungeon | Boss count | Notes |
|---|---|---|
| Blackrock Depths | 4 | Lord Incendius, Magmus, Emperor Dagran Thaurissan, Princess Moira Bronzebeard |
| Lower Blackrock Spire | 6 | Highlord Omokk → Overlord Wyrmthalak |
| Upper Blackrock Spire | 4 | Warchief Rend Blackhand → General Drakkisath |
| Scholomance | 8 | Rattlegore → Darkmaster Gandling |
| Stratholme (Live) | 4 | Archivist Galford, Balnazzar, Timmy the Cruel, The Unforgiven |
| Stratholme (Undead) | 6 | Magistrate Barthilas → Lord Aurius Rivendare |
| Baradin Hold | 4 | Glagut, Nazrasash, Calypso, Pirate Lord Blackstone |

**Stratholme side detection.** `GetInstanceInfo()` returns "Stratholme" for both sides — the addon can't tell them apart from the API alone. On entry, the frame shows ALL 10 bosses tagged "(live)" / "(undead)" with everything greyed out. The first boss kill resolves the side, prints `Stratholme side detected: Live/Undead` to chat, and the frame redraws showing only that side's roster.

**Frame layout** (`/epogarmory dungeon` or auto-opens on entry):

- Title: "EpogLogs - Dungeon Run"
- Dungeon name with side suffix when relevant
- Big timer (M:SS or H:MM:SS for long runs) — focal element
- Status badge: `IDLE` / `IN PROGRESS (n/N bosses)` / `COMPLETE` (green when all bosses down)
- Logging status row: `Logging: ACTIVE` (green) / `Logging: OFF` (red)
- One-time prompt on entry: "Start /combatlog for this run? [Yes] [No]" — non-secure (LoggingCombat isn't protected)
- Boss list with ✓/- markers, killed bosses highlighted, unkilled greyed
- Bottom toggle button: "Start logging" / "Stop logging" — manual control after the prompt is dismissed

**Auto-start logic.** No — per user preference, the addon does NOT auto-start `/combatlog`. The on-entry prompt asks once and respects "No" for the remainder of the run. If the user declines, they can still manually start logging via the bottom toggle button. This contrasts with the dummy frame's auto-start (which defaults on).

**State tracking.**

- `currentDungeon` — key into `DUNGEONS` table, set by `DetectDungeon()` on zone change
- `stratSide` — `"live"` / `"undead"` / nil, resolved on first boss kill in Stratholme
- `dungeonStartTime` — `GetTime()` when entered, used for the live timer
- `bossKills` — set, `bossName → true` on each `UNIT_DIED` CLEU event
- `loggingActive` — mirror of `LoggingCombat()` state (the API has no getter, so we shadow it)
- `promptShown`, `userDeclinedLog` — per-run flags so the prompt fires at most once

**Detection.** `IsInInstance()` + `GetInstanceInfo()` on `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`. Instance type must be `"party"` or `"raid"` (Baradin Hold is technically a raid). Lookup is by instance name against the hardcoded `DUNGEONS` table. Unknown instances → frame stays idle, doesn't interfere.

**Boss kill detection.** `COMBAT_LOG_EVENT_UNFILTERED` filtered for `UNIT_DIED` events with `destName` matching a boss in the current dungeon's roster. No source-flag check (someone else in the group might land the killing blow). De-dupe via the `bossKills` set so multi-phase boss "deaths" don't double-count.

**Files added**: `EpogArmoryDungeon.lua` (~400 lines). Added to TOC after `EpogArmoryDummy.lua`.

**Slash**: `/epogarmory dungeon` — toggle the frame manually. Help text updated.

**Not in this cut (deferred to v1.7.4 if user asks):**
- Trash bucket tracking. Each dungeon's epoglogs rules also specify "kill at least N of [boss-category] mobs" as a leaderboard requirement (e.g. Stratholme Live needs 25 of various Skeletal/Cadaver types + 14 Crimson Gallant/Guardsman/etc.). Implementing OR-group tracking would add ~200 lines and need its own UI section. Bosses-only covers the user's stated need ("which bosses was killed, which is missing").
- History panel. The dummy module persists `dummyFights[]` for past runs; the dungeon module currently doesn't save run records anywhere. Easy to add via `EpogArmoryDB.dungeonRuns[]` once we know what the leaderboard intake wants.
- Verdict-style upload guidance. Currently no chat-line at run end pointing the user at the log filename. Should match the dummy module's pattern once we have the file open.

Patch-level — no public release, no standalone repo sync, mesh auto-update notification stays silent. Will roll v1.7.1 + v1.7.2 + v1.7.3 together into v1.8.0 once user-tested.

---

## EpogArmory v1.7.2 — Strict 10s validate window + countdown (internal) *(2026-05-20)*

Patch-level bump (1.7.1 → 1.7.2). Tightens the validate-click window from a 120s open-ended timeout to a strict 10-second window with a visible countdown. Driven by the epoglogs.com team's request after they shipped server-side 90s truncation (v0.83.20) — the leaderboard is now fair regardless of click timing, so the addon's job is purely UX: make it obvious when the click window opens and closes.

**The change in numbers:**

| Before (v1.7.1) | After (v1.7.2) |
|---|---|
| Button shows at T+1:20 | Button shows at T+1:20 *(unchanged)* |
| Label: `VALIDATE PARSE` (static) | Label: `VALIDATE (10)` → `VALIDATE (9)` → ... → `VALIDATE (1)` *(live countdown)* |
| Timeout: 120s (`POST_COMBAT_HARD_TIMEOUT`) | Timeout: 10s (`VALIDATE_WINDOW_SEC`) |
| On timeout: generic `Log: INVALID - rejected on upload` | On timeout: `LOG FAILED - click Reset to try again` *(specific, actionable)* |

**Why 10s?** Matches `LOG_DURATION_SEC - MARKER_TIME_SEC` (90 − 80). The addon's `LoggingCombat(false)` is called by `FinishFight`, which fires either when the user clicks Validate (any time during the 10s) or when the window expires. Either way the combat log file closes at or before T+1:30, which keeps the marker line within ~0-1s of the last event in the file — comfortably inside the site's `MAX_MARKER_TO_END_S = 30` acceptance window.

**Why a countdown?** The earlier flow was "Validate button appears at T+1:20, nothing visibly changes, somewhere around T+1:30 the addon stops on its own." Multiple users reported "did it work? am I done?" confusion. The countdown removes that — the user sees exactly how much time they have to click, and exactly what happened if they missed.

**Implementation details:**

- New constant `VALIDATE_WINDOW_SEC = LOG_DURATION_SEC - MARKER_TIME_SEC` (10s). Removed the old `POST_COMBAT_HARD_TIMEOUT = 120` constant; it was the only timeout in the stopping branch and is now obsolete.
- `OnTick` stopping-state branch: hard-fail with reason `"validate window expired (10s)"` once `stoppingFor >= VALIDATE_WINDOW_SEC` and no marker has been emitted. Gated on `not markerEmitted` so a click in the final 100ms still wins the race.
- `UpdateUI` stopping-state `show-button` sub-state: computes `remaining = math.ceil(VALIDATE_WINDOW_SEC - stoppingFor)` each tick and sets the button label via `f.validateBtn:SetText(...)`. Clamped to `math.max(1, ...)` so we never render "0" or negative.
- `UpdateUI` stopped-state: detects `invalidReasons["validate window expired (10s)"]` and renders the dedicated `LOG FAILED - click Reset to try again` message instead of the generic INVALID line.
- `OnLeaveCombat` comment updated to reference `VALIDATE_WINDOW_SEC` instead of the removed constant.

**Test command unaffected.** `/epogarmory testvalidate` still works — it sets `testMode = true` which short-circuits `OnTick` entirely, bypassing both the validation gate and the new 10s timeout. The validate button stays clickable indefinitely in test mode, which is the intended behavior for marker round-trip testing.

**Site-side coordination.** None needed — the site validator (`lib/dummy-marker-validator.js`) is already permissive enough to accept whatever this version produces. Per the epoglogs handoff doc, the site is at v0.83.21 and accepts both Fishing (all 5 ranks: 7620/7731/7732/18248/33095) and Basic Campfire (818) markers. The new strict window only ever produces markers earlier in the log (T+1:20 to T+1:30 instead of up to T+3:20), so all timing constraints are easier to satisfy, not harder.

Patch-level — no public release, no standalone repo sync, mesh auto-update notification stays silent. Will roll v1.7.1 + v1.7.2 together into v1.8.0 once tested.

---

## EpogArmory v1.7.1 — Marker fallback + stricter matcher + testvalidate (internal) *(2026-05-19)*

Patch-level bump (1.7.0 → 1.7.1). Three related changes to the dummy-parse marker.

**Basic Campfire fallback.** The Validate button's macro now runs two `/cast` lines:

```
/cast Fishing
/cast Basic Campfire
```

This covers a corner case where a player has a Fishing Pole equipped during the parse — `/cast Fishing` then succeeds and produces a `SPELL_CAST_START` instead of the `SPELL_CAST_FAILED` line we want. If that player also has Cooking learned, `/cast Basic Campfire` provides a fallback marker (fails with "Try this outside" or similar in a city). The accepted-marker table `MARKER_SPELL_NAMES` is keyed by spell name for O(1) CLEU lookup.

**Stricter CLEU matcher.** The marker check used to accept either `SPELL_CAST_START` or `SPELL_CAST_FAILED`. It now accepts only `SPELL_CAST_FAILED`. The reason: the site contract for upload acceptance only matches FAILED. If the addon accepted START locally but the site didn't, a pole-equipped player would see CLEAN in-game but get their upload rejected — bad UX. Tightening the addon side keeps the in-game verdict honest about what the site will actually accept.

**Site impact:** the handoff brief in `memory/handoff_epoglogs_dummy_validation.md` needs an update — the site should now accept either `"Fishing"` OR `"Basic Campfire"` as the marker spell name in the SPELL_CAST_FAILED line. Spell IDs to allow: 7620 (Fishing), 818 (Basic Campfire). All other timing + GUID + dummy-presence constraints unchanged.

**New slash: `/epogarmory testvalidate`.** Jumps straight into a synthetic "stopping" state with the green Validate button visible immediately, no dummy fight required. Starts `LoggingCombat(true)`, captures the filename, and waits for the user to click Validate. The CLEU listener then confirms whether the SPELL_CAST_FAILED line landed (success = "MARKER VERIFIED" + log filename; failure = "MARKER NOT VERIFIED" with diagnostic guidance). Skips aura validation and the post-combat hard timeout via a new `testMode` flag in OnTick. Doesn't write to the fight history. Refuses to run if a real parse is currently in progress.

Useful for: validating the marker round-trip after the v1.7.1 multi-spell macro change, debugging if a user reports the marker not landing, and one-shot smoke-testing on a new character without finding a training dummy.

Patch-level — no public release, no standalone repo sync, mesh auto-update notification stays silent.

---

## EpogArmory v1.7.0 — Dummy parse validation *(2026-05-19)*

New module `EpogArmoryDummy.lua` validates target-dummy combat logs against a clean-self-only rule and stamps an in-log marker so epoglogs.com can gate dummy parses without requiring users to bundle SavedVariables uploads. Addon is no longer armory-only — the dummy parse window is its second top-level surface.

**The marker scheme** (verified empirically against Epoch's combat log writer):

The user clicks a `SecureActionButtonTemplate` button labelled "Validate" after T+1:20. Its `macrotext` attribute is `/cast Fishing`. Without a fishing pole equipped this attempt fails immediately and Epoch's combat log writes:

```
SPELL_CAST_FAILED,<playerGUID>,"<playerName>",0x511,0x0,nil,0x80000000,7620,"Fishing",0x1,"Must have a Fishing Pole equipped"
```

Site parses for that line within the 1:30 log window. Exactly one such line from the player, timestamped ≥1:18 after the first event, = addon-validated parse. The site brief is in `memory/handoff_epoglogs_dummy_validation.md`.

**Why a secure user click, not addon-script?** We tested `CastSpellByName("Fishing")` from a slash command and confirmed it produces no CLEU entry at all on Epoch — only hardware-event-triggered secure casts make it into the combat log file. So the marker has to be authored by a user click on a secure button, which also conveniently makes the file impossible to forge from addon code on a different client.

**Why Fishing?** Every character can attempt it (no spellbook gating), it always fails without a fishing pole (deterministic SPELL_CAST_FAILED), the failure reason string is stable across the locales we ship to, and it doesn't conflict with any combat-state ability. The red `UIErrorsFrame` flash that normally accompanies the failure is suppressed for ~0.8s around the click so the mechanism stays opaque to users.

**Lifecycle**

```
[IDLE] —(combat starts with dummy in city)→ [LOGGING]
                                                │
                                       T+1:20: validate button fades in
                                       (user click) → marker line in log
                                                │
                                       T+1:30: LoggingCombat(false) → [STOPPED]
                                       or earlier via Reset / 3s idle in tail
                                                │
                                                ▼
                                             chat verdict + filename
```

- **Continuous aura validation** throughout the fight (UNIT_AURA events + 0.25s timer-driven fallback). Any disallowed buff/debuff flips `validThroughout` permanently false — no recovery within the same fight.
- **Validate button only appears (`SetAlpha 1`) after T+1:20 and only if `validThroughout` is still true.** Fights that degraded mid-fight never get the option to stamp.
- **Validate button is visible during combat.** Players often get stuck in combat after a dummy burn; the button has to be clickable then. `SetAlpha`-based visibility is used because `Show`/`Hide` on frames containing a secure child is blocked by combat lockdown — but alpha changes aren't.
- **Combat-log filename is captured** at `LoggingCombat(true)` time via `date("Logs/%Y-%m-%d-%H.%M.%S WoWCombatLog.txt")` and surfaced in the verdict line so the user knows exactly which file to upload.
- **Auto-stop triggers**: Reset click (cancels without validation), Validate click (after CLEU confirms the marker landed), 3-second idle gap during the 1:20→1:30 tail, hard timeout at T+1:30, or 120s post-combat safety stop.

**Allowed aura sources** (`ALLOWED_CASTERS`):
- `"player"` — self-casts
- `"pet"` — all class summons use this unit token (Hunter pet, Warlock demons, Mage Water Elemental, Priest Shadowfiend, Shaman Greater Elementals, DK Ghouls, Druid Treants)
- `"vehicle"` — vehicles you control
- Substring `"Mana Potion"` in the aura name — allowed even when caster is nil

Anything else (party/raid members, other players' pets, trinket guardians applying auras under their own GUID, flask buffs, foreign drums, weapon oils, Well Fed) invalidates the fight.

**UI frame** (`/epogdummy` or auto-opens when targeting `"Training Dummy"` in a city):

- Title: "EpogLogs - Dummy Parse"
- State badge: IDLE / ARMED / LOGGING / STOPPING / STOPPED
- **Big DPS readout** (`GameFontNormalHuge`) as the focal element — live during the fight, calculated from our own CLEU damage tracking (no Recount/Skada dependency). Total damage subtitle beneath it.
- Progress bar (12px tall) with marker tick at the 1:20 position
- Timer "0:18 / 1:30" beneath the bar
- Player Auras list with per-row ✓/✗ + caster
- Target Debuffs list (same format)
- Auto-start checkbox (`config.dummyAutoLog`, defaults on) — addon starts logging automatically the instant combat begins with a dummy targeted
- Secure Validate button (appears T+1:20, in-combat-safe) + Stop / Reset button below

**Chat verdict at fight end**:

```
EpogArmory: ✓ CLEAN dummy parse — log is valid for upload.
  - upload this file: Logs/2026-05-19-22.40.27 WoWCombatLog.txt

(or if invalid:)
EpogArmory: ✗ INVALID dummy parse — log not stamped.
  - player buff: Flask of Endless Rage (from player)
  - target debuff: Earth Shock (from Thrall)
```

**Persistence**

`EpogArmoryDB.dummyFights[]` keeps the last 50 fight records (endTime, durationSec, dummyName/GUID, valid bool, invalidReasons list, markerEmitted bool, markerVerified bool, addonVersion). Sidecar backup if a user uploads SavedVariables alongside the log.

**Backward compatibility**

- New file, new module, doesn't touch any existing code paths.
- New SavedVariables fields (`dummyFights[]`, `config.dummyAutoLog`) are additive; defaults applied on first PLAYER_LOGIN after upgrade.
- Wire format unchanged — no mesh impact.
- Older clients in the mesh see no behavior change.

Minor bump (1.6.0 → 1.7.0). v1.6.1 was an internal test version; this is the first public release of dummy parse validation.

---

## EpogArmory v1.6.0 — Auto-sync + quality controls *(2026-05-06)*

Consolidated release covering the v1.5.1–v1.5.3 iteration cycle. Headline feature: background auto-sync. Supporting changes: tighter quality gates on what enters the mesh, and a long-standing PvP-routing gap closed.

**Background auto-sync**

No more `/epogarmory syncfrom <name>` for every peer you want to catch up on. A new background ticker picks one reachable peer every 5 minutes and starts a sync via the existing wire path. Slow and steady — bandwidth-friendly even in a 100-person guild.

- 24h per-peer cooldown (`peerInfo[name].lastSyncedFrom`), persisted in SavedVariables so it survives `/reload` and re-login.
- Selection criteria: peer must be reachable (in guild online / party / raid), heard from in last 24h, have ≥10 stored scans, off cooldown, not already syncing.
- Ties broken by largest peer DB first — most data per sync.
- Respects the existing 3-concurrent cap and 90s post-login delay before first attempt.
- Same wire path as manual `/syncfrom` — both write `lastSyncedFrom`, so a manual sync satisfies the auto-sync gate.
- Default-on for new and upgrading users. Toggle via `/epogarmory autosync on|off|status`.

**Quality gates**

Three new rules for what qualifies for the mesh:

- **Average ilvl floor**: `MIN_AVG_ILVL = 55`. Sets averaging below 55 ilvl across filled non-cosmetic slots are rejected as leveling gear. Sparse-cache safe — only fires when ≥10 valid ilvl reads are available, so fresh installs aren't false-rejected during warm-up.
- **Three new utility-item blacklist patterns** added at `UTILITY_ITEM_NAMES_ANY_SLOT`: Argent Dawn Commission, Finkle's Skinner, Skull of Impending Doom. Name-based (not itemID) so Ascension's server-side ID reassignment doesn't break the filter.
- **Offhand always optional**: the v1.3.3 "required unless mainhand is 2H" conditional was too strict for titan-grip swaps and mid-fight weapon configs. Slot 17 now joins shirt (4) and tabard (19) as never-required.

**PvP-set routing hardening**

Insignia/Medallion/Battlemaster's trinket → `sets["pvp"]` routing was structurally correct but had a silent-fail gap: `EntryGearLooksPvP` resolved trinket names via `GetItemInfo`, which reads WoW's *async* client cache. Freshly-received itemIDs sometimes had no resolved name when the routing decision happened in `Ingest` — result, the set quietly went to a talent-tree key instead of `sets["pvp"]`.

Fixed with a new `ResolveItemName(iid)` helper that checks `EpogItemCacheDB` (seeded synchronously from v1.2+ item-info hints) before falling back to `GetItemInfo`. Applied to both receiver and sender paths.

Added a `dprint` log when routing to `sets["pvp"]` so users can verify the gate fires on real scans (toggle via `/epogarmory debug`).

**Refactor: shared sync-start path**

Both `/syncfrom` and auto-sync now go through one `StartSyncFromPeer(name, days)` helper. The slash command dropped from ~80 lines of inline sync-start logic to a thin wrapper around the helper. Reduces drift risk between the two paths.

**Backward compatibility**

- Wire format unchanged (no new fields added in v1.5.x).
- New SavedVariables fields are additive and optional: `peerInfo[name].lastSyncedFrom`, `config.autoSync`. Missing values treated as never-synced and default-on respectively.
- No DB wipe on update. Existing accumulated mesh data preserved.
- Mixed-version mesh works: v1.6 peers respond to legacy clients' sync requests the same as v1.5 peers; older clients receive v1.6 broadcasts cleanly.

---

## EpogArmory v1.5.3 — PvP-set routing hardening *(2026-05-06)*

Audit pass on the "Insignia/Medallion/Battlemaster's → sets\[\"pvp\"\]" routing. The logic was structurally correct (centralized at one write site in `Ingest`, receiver recomputes locally instead of trusting wire pos 31) but had a real gap on the receiver side.

**The gap:** `EntryGearLooksPvP` resolved trinket names via `GetItemInfo(itemID)`, which reads the WoW *client* cache. That cache is populated by async server queries — a freshly-received itemID may not yet have a name when the routing decision happens in `Ingest`. Our own `EpogItemCacheDB` IS seeded synchronously from v1.2+ item-info hints (and from the scanner's own scans), and contains server-correct names. But the resolver wasn't consulting it.

**Fix:** new `ResolveItemName(iid)` helper checks `EpogItemCacheDB[iid].name` first, falls back to `GetItemInfo`. Used by both:
- `EntryGearLooksPvP` (receiver path) — primary beneficiary
- `UnitLooksPvP` (sender path) — symmetry, helps inspect-scans where the inspected unit's items aren't yet in the client cache

**Diagnostic log added.** When a scan routes to `sets["pvp"]`, a `dprint` line fires:
```
[route] Defcom → sets["pvp"] (PvP trinket detected in slot 13/14)
```
Toggle via `/epogarmory debug` to verify the gate is firing in real conditions.

**No behavior change for the success case** — Insignia trinkets already routed correctly when the name resolved. This patch closes the silent-fail window where the name was momentarily unresolvable during a fresh broadcast ingest.

**Confirmed correct (pre-existing):**
- Only one write site: `existing.sets[group] = {...}` at line 2061
- `group = "pvp"` if `EntryGearLooksPvP(entry.gear)` else `group = DominantTree(entry.spec)` — no third option, no bypass
- Trinket scan slot-restricted to `TRINKET_SLOTS = {13, 14}` — shoulder/shield items with "Insignia" in the name don't false-trigger
- Patterns `{"Insignia", "Medallion", "Battlemaster's"}` cover all standard WoW 3.3.5 PvP trinkets

Patch-level bump (1.5.2 → 1.5.3) — mesh auto-update notification stays silent.

---

## EpogArmory v1.5.2 — Stricter quality gate *(2026-05-06)*

Tighter rules on what qualifies for the mesh. Reduces low-value entries that pollute the DB and the upload to epoglogs.com.

**New blacklist entries** (name-matched at `UTILITY_ITEM_NAMES_ANY_SLOT`):
- Argent Dawn Commission — +rep trinket, common Stratholme leveling drop
- Finkle's Skinner — skinning-only one-handed dagger (Stratholme drop)
- Skull of Impending Doom — novelty trinket (Wailing Caverns)

Name-based rather than itemID because Ascension reassigns vanilla item IDs server-side; names stay stable across reassignments.

**Average item-level gate.** New `MIN_AVG_ILVL = 55`. Sets where the average ilvl across filled non-cosmetic slots (shirt + tabard excluded) falls below 55 are rejected. Catches leveling alts and quest-gear loadouts that aren't raid-relevant. Threshold picks the floor of L60 dungeon-blue territory; pure greens average ~45-50, full T0/dungeon-set ~55-58, raid epics 65+.

Implementation detail: gate only fires when we have ≥10 valid ilvl reads. If most items aren't yet in the item cache (fresh installs, cold mesh), we let the scan through and catch it next time when the cache has settled. Avoids false rejections during the warm-up period.

**Offhand always optional.** The prior v1.3.3 rule conditionally required slot 17 unless mainhand was an `INVTYPE_2HWEAPON`. That was too strict — fury warriors swapping titan-grip configs, prot warriors going 2H briefly mid-fight, etc. would fail the gate. Slot 17 (offhand) is now in the same category as 4 (shirt) and 19 (tabard) — never required.

Removed the now-orphaned `IsTwoHandRef` helper (only used by the conditional offhand check).

Patch-level bump (1.5.1 → 1.5.2) — mesh auto-update notification stays silent. Bundled with the v1.5.1 auto-sync into the eventual v1.6 minor release.

---

## EpogArmory v1.5.1 — Background auto-sync *(2026-05-06)*

The `/epogarmory syncfrom` command catches you up on a peer's stored scans, but you had to type it manually for each name. v1.5.1 adds a background ticker that does the same thing automatically — slow and steady, one new peer every few minutes, with a 24h per-peer cooldown so the same person doesn't get drained over and over.

**Behavior**

- Every `AUTO_SYNC_TICK_INTERVAL` (5 min), the ticker picks one reachable peer and starts a sync. Uses the same wire path as `/syncfrom` — capped at `SYNC_MAX_CONCURRENT` (3) simultaneous active syncs.
- Per-peer cooldown: `AUTO_SYNC_PEER_COOLDOWN` (24h). Tracked at `EpogArmoryDB.peerInfo[name].lastSyncedFrom`, so it survives `/reload` and re-login.
- Candidate selection: peer must be (a) currently reachable — in our guild online, party, or raid; (b) heard from in the last 24h (`peerInfo.lastSeen`); (c) have at least 10 stored scans (`AUTO_SYNC_MIN_DBSIZE`); (d) off the per-peer cooldown; (e) not already syncing.
- When multiple candidates qualify, picks the **largest-DB peer first** — most data to gain per sync.
- First attempt fires `AUTO_SYNC_INITIAL_DELAY` (90s) after `PLAYER_LOGIN` so the guild roster, peer pings, and outQueue have time to settle.
- Defaults to last 7 days of scans per request (matches `/syncfrom <name>` default).

**Manual sync still works the same** — `/syncfrom <name> [days]` always starts a sync regardless of cooldown. Both manual and auto syncs write `peerInfo[name].lastSyncedFrom`, so a manual sync also satisfies the auto-sync's 24h gate for that peer.

**Config + slash control**

- `EpogArmoryDB.config.autoSync` — boolean, defaults to `true` for new and upgrading users.
- `/epogarmory autosync` — show status (on/off, next attempt countdown, eligible peer count, on-cooldown count).
- `/epogarmory autosync on|off` — toggle.

**Refactor: shared sync-start path**

Both manual `/syncfrom` and auto-sync now go through one `StartSyncFromPeer(name, days)` helper. The slash handler dropped from ~80 lines of inline sync-start logic to a thin wrapper around the helper. Reduces drift risk between the two paths.

**Backward compatibility**

- `peerInfo[name].lastSyncedFrom` is a new field — pre-v1.5.1 entries simply don't have it, treated as 0 (never synced) so the first auto-sync candidate scan picks them up immediately.
- No wire format change. Sync protocol unchanged. Pre-v1.5.1 peers respond to auto-sync requests the same as manual ones.
- `EpogArmoryDB.config.autoSync` only added on first run after upgrade — existing configs keep their values.

Patch-level bump (1.5.0 → 1.5.1) — mesh auto-update notification stays silent. Public release deferred until tested in real conditions; the monorepo has the change and a future v1.6 minor will surface it to users.

---

## EpogArmory v1.5.0 — Stats overview, Guild column, talent tree polish *(2026-05-05)*

Consolidated release covering the v1.4.1–v1.4.6 iteration cycle. Headline features: a full Stats overview panel showing real character-pane numbers, a Guild column in the Scanners view, and a visual pass on the talent tree to bring it closer to Blizzard's PlayerTalentFrame look.

**Stats overview panel**

A new Stats button on the inspect frame opens a side-panel showing aggregated stats for the active set. Layout: Stats | Inspect | Talents when all three are open.

- **Live character snapshot at scan time.** New `CapturePlayerStats(unit)` reads `UnitStat` / `UnitArmor` / `UnitAttackPower` / `UnitRangedAttackPower` / `UnitDamage` — these all work on inspected unit tokens, so the snapshot fires for both self-scans and inspect-scans of others. Player-only APIs (`GetCritChance`, `GetCombatRatingBonus`, `GetSpellBonusDamage`, `GetDodgeChance`, etc.) only fire when scanning self; for inspect-scans of others the panel falls back to derived-from-rating sums.
- **Sections**: Base Stats (STR/AGI/STA/INT/SPI/Armor) + Melee (Damage/Speed/Power/Hit/Crit/Haste/Expertise) + Ranged + Spell + Defense.
- **Combines rating-based and tooltip-based stats**: Vanilla L60 gear stores percentages as tooltip text (`+1% crit`, parsed into `entry.tooltipStats`) instead of as ratings. New `CombinePct` helper merges both sources into one displayed % so Vanilla, TBC, and WotLK gear all sum correctly.
- **Wire field 43** carries the encoded snapshot (`str=74,agi=339,sta=220,armor=2399,mAP=722,...`). Stored as `set.charStats`, persisted in `EpogArmoryDB`, eventually flowing to epoglogs.com via the standard upload path.
- **Sub-L80 conversion**: rating→% uses WotLK level-80 constants. Sub-80 inspects show slightly inflated %s but ordering is correct.

**Scanners view: Guild column**

- New wire field 42 carries the scanner's guild name (`GetGuildInfo("player")`). Receivers persist to `peerInfo[name].guild`.
- New "Guild" column inserted between Name and Contrib in the Scanners-view leaderboard. Self-row guild populated live from the API since `peerInfo` never tracks self.
- Forward-compat: pre-v1.5 senders without field 42 don't blow away existing guild values when they broadcast.

**Frame sizing & layout**

- Inspect frame: 320 → 360 wide. Slot icon offsets pushed inward (15 → 35 left/right; 55 → 75 for bottom-row weapons) so items have more breathing room around the edges. Icon spacing in the middle gap is unchanged — only outer padding grew.
- Browser frame: 320 → 380 wide to fit the new Guild column.
- Talent frame: now 360 wide (matching inspect) and 600 tall. Drag disabled — talents always docks to the inspect frame's right edge via a relative anchor (`TOPLEFT → TOPRIGHT`), so dragging the inspect frame carries talents along automatically. Previously letting talents drag independently broke the "stick" relationship.
- Stats button grouped horizontally next to Talents on the inspect frame (`Talents | Stats` row), with the spec-tab row dropped 10px for clearance.

**Talent tree visual pass**

Closer to Blizzard's `PlayerTalentFrame` look:
- Cell size: 36 → 40 px
- Horizontal gap: 6 → 12 px, **vertical gap: 6 → 14 px** (the biggest visual change — in-game has noticeably more vertical breathing room)
- Brighter rank-state colors: max-rank cells glow gold instead of dim amber, in-progress cells use saturated green instead of muted, empty cells stay near-black
- Frame height bumped from 540 to 600 to accommodate the larger cells

**Defense section**

`GetCombatRatingBonus(3/4/5)` only returns the rating-derived bonus — a Hunter with no dodge rating still has 4-5% dodge from base Agility. Switched to `GetDodgeChance / GetParryChance / GetBlockChance` for the totals. Defense skill uses `UnitDefense("player")` (base + rating modifier).

**Backward compatibility**

- Wire format additive — pre-v1.5 receivers ignore positions 42 (senderGuild) and 43 (charStats) silently.
- Pre-v1.5 cached entries render with v1.4.0-style item-only fallbacks. Title shows `(item-only)` indicator.
- No DB wipe on update. All accumulated mesh data preserved.
- `MigratePlayers` continues to handle pre-v0.13 flat entries and v0.13+ unkeyed sets.
- Mixed-version mesh works: v1.5 senders carry the new fields, older senders don't, receivers handle both.

**Test track conclusion (v1.4.1–v1.4.5 internal)**

A test build with `REQUIRE_REALITY_AURA = false` validated whether the v1.4.0 settle (400ms) + verify (1.5s) pipeline could replace the aura interlock. Result: no — Ascension/Epoch's transmog override holds the cosmetic itemID well past the 1.9s combined window for inspected players, so without the aura we just broadcast junk gear. The interlock is back on. Flag kept (default `true`) for one-line revert if server behavior ever changes.

---

## EpogArmory v1.4.6 — Reality Recalibrators interlock re-enabled *(2026-05-05)*

**Test result from v1.4.1 → v1.4.5: the aura interlock is genuinely required on Epoch.** Without `Reality Recalibrators`, the v1.4.0 settle (400ms) + verify (1.5s) pipeline isn't sufficient — Ascension/Epoch's transmog override keeps returning cosmetic itemIDs for inspected players past the 1.9s combined window, so scans broadcast junk gear. The settle+verify is still useful for catching short flips when the aura *is* active, but it can't replace the aura.

`REQUIRE_REALITY_AURA = true` (was `false` in v1.4.1-v1.4.5 test branch). All three interlock points (`BuildPayload`, `ScanRoster`, `TryInspect`) are gating on the aura again, matching v1.4.0 behavior.

The flag itself is kept rather than removed — flipping back to `false` is a one-line revert if we want to re-test (e.g., if server transmog behavior changes). Diagnostic surfaces (`/epogarmory status`, `/epogarmory aura`, browser banner, minimap tooltip) continue to honor the flag and would correctly say "TEST MODE: scanning anyway" if it ever flips false again.

Patch-level bump (1.4.5 → 1.4.6) — mesh auto-update notification stays silent.

---

## EpogArmory v1.4.5 — Defense totals + talent tree visual pass *(2026-05-05)*

**Defense section was showing 0% for everything**

`GetCombatRatingBonus(3/4/5)` only returns the rating-derived bonus — a Hunter with no dodge rating still has 4-5% base dodge from Agility, but my v1.4.4 captured the rating component (0) and displayed 0%. Switched to:
- `GetDodgeChance()` — total dodge incl. base + Agility + items + buffs
- `GetParryChance()` — same for parry
- `GetBlockChance()` — same for block
- `UnitDefense("player")` — for Defense skill (base + rating modifier)

Display row labels updated: "Defense Rating: N (+ skill)" → "Defense: N skill" when live snapshot present (matches in-game character pane wording).

**Talent tree visuals**

Closer to Blizzard's `PlayerTalentFrame` look:
- Cell size: 36 → 40 px
- Horizontal gap: 6 → 12 px
- **Vertical gap: 6 → 14 px** (the biggest visual change — the in-game tree has noticeably more vertical breathing room than horizontal)
- Frame height: 540 → 600 (to fit 9 rows × 54 px pitch + 86 top + 42 bottom padding)
- Brighter rank-state colors: max-rank cells now glow gold `(1.0, 0.78, 0.18)` instead of dim amber, in-progress cells use saturated green `(0.18, 0.78, 0.22)` instead of muted, empty cells stay near-black

**About the in-game character pane showing 0% hit chance**

EpogArmory's stat-capture is read-only — `UnitStat`, `UnitArmor`, `GetCombatRatingBonus`, etc. cannot modify game state. If the in-game pane shows 0% but our snapshot showed 6%, it's because the gear/buff state changed between the snapshot and the current view (e.g., unequipped a hit-rating item, lost an aura). No bug from our side.

Patch-level bump (1.4.4 → 1.4.5) — mesh auto-update notification stays silent.

---

## EpogArmory v1.4.4 — Stats panel: live character snapshot *(2026-05-05)*

The v1.4.3 panel summed only what was literally on items, missing everything the in-game character pane shows: race+level base attributes, class AP formulas (warrior STR×2, hunter AGI×2), weapon damage with AP scaling, talent multipliers (Toughness +Stamina, Durability, etc.), and active buff effects. So a L60 Hunter with 339 Agility on the character pane showed only 180 in EpogArmory (item-only sum).

**New: live character-stat snapshot at scan time**

- New `CapturePlayerStats(unit)` reads from `UnitStat / UnitArmor / UnitAttackPower / UnitRangedAttackPower / UnitDamage` — these all work on inspected unit tokens (`party1`, `raid5`, etc.), so the snapshot fires for both self-scans and inspect-scans of others.
- Player-only APIs (`GetCritChance`, `GetCombatRatingBonus`, `GetSpellBonusDamage`, `GetManaRegen`) only fire when scanning self. For inspect-scans of others those fields stay unset; the UI falls back to derived-from-rating sums for those rows.
- New wire field at position 43 carries the encoded stats blob (`str=74,agi=339,sta=220,...`). `EncodeCharStats` / `ParseCharStats` handle the round-trip; values stored as `set.charStats` per spec, mirroring the `talentRanks` shape.

**Stats panel display**

- Each row now prefers `set.charStats[csKey]` over the item-derived fallback. New helpers `csNum(csKey, fallback)` and `csPct(csKey, fallback)` swap in the live value when present.
- Title shows `(item-only)` in grey when looking at a pre-v1.4.4 cached entry that has no snapshot. Fresh scans omit the suffix — implies the live snapshot is being used.
- Weapon damage row uses `cs.wMin/cs.wMax` (UnitDamage output, includes AP scaling) when available, falls back to weapon item's intrinsic damage range otherwise.
- Armor row label changes from "Armor (bonus)" to "Armor" when the live snapshot is used (it's the effective armor including base+items+buffs, not the GetItemStats bonus alone).

**Backward compatibility**

- Wire format additive — pre-v1.4.4 receivers ignore field 43 silently.
- Pre-v1.4.4 cached entries (no `charStats`) render with the item-only fallback values from v1.4.3 — no breakage. Re-scan to upgrade.
- Mixed-version mesh: v1.4.4 senders carry the snapshot; v1.4.3- senders don't. Receivers handle both.

Patch-level bump (1.4.3 → 1.4.4) — mesh auto-update notification stays silent.

---

## EpogArmory v1.4.3 — Stats panel fixes *(2026-05-05)*

Three issues from v1.4.2 reported in testing:

- **Stats button hidden behind spec-tab buttons.** The new Stats button stacked vertically below Talents at y=-87, but the spec-tree tab row sits at y=-82 — 1px overlap. Now grouped horizontally next to Talents (`Talents | Stats` on row 3), and the spec tab row dropped from y=-82 to y=-92 for clearance against the Talents/Stats button row.
- **Stats panel content overflowed the frame bottom.** ~35 rows × 16px line height plus 4 section gaps and 5 header expansions came out to ~594px, but the frame was only 540 tall. Frame bumped to 640. Line height reduced 16→14 so the content sits comfortably inside even with the Defense section fully populated for tank loadouts.
- **All Hit/Crit/Haste/Expertise rows showed 0%.** L60 Vanilla-era gear stores percentage stats as tooltip text (`+1% crit`) rather than rating values — the rating system was introduced in TBC. EpogArmory parses these into `entry.tooltipStats` (keyed `CRIT_PCT`, `HIT_PCT`, etc.) but the Stats panel was only reading `entry.stats` (the GetItemStats output). New `CombinePct` helper merges both: ratings divided by the L80 conversion + tooltip pcts added directly. Vanilla, TBC, and WotLK gear all sum correctly into one displayed %.

Removed orphaned `FmtPct` helper (replaced by `CombinePct`). Patch-level bump again — mesh auto-update notification stays silent.

---

## EpogArmory v1.4.2 — UI: Guild column, frame sizing, Stats panel *(2026-05-05)*

Internal patch build (test track continues — aura interlock from v1.4.1 still disabled). Patch-level bump means no auto-update notification on the mesh.

**Frame sizing**
- **Inspect frame**: 320 → 360 wide. Slot icon offsets pushed inward (15→35 left/right, 55→75 for bottom-row weapons) so items have more breathing room around the edges. Icon spacing in the middle (between left/right columns) is unchanged — only the outer padding grew.
- **Browser frame**: 320 → 380 wide to fit the new Guild column without squeezing other Scanners-view columns.
- **Talents frame**: now matches the inspect frame's dimensions (360×540). Grid centered horizontally inside the wider frame. Drag disabled — talents always docks to the inspect frame's right edge via a relative anchor (`TOPLEFT → TOPRIGHT`), so dragging the inspect frame carries talents along automatically. Previously letting talents drag independently broke the "stick" relationship.

**Scanners view: Guild column**
- New wire field at position 42 carries the scanner's guild name (`GetGuildInfo("player")` at scan time). Wire-control chars (`^`, `|`) stripped defensively.
- `ParsePayload` reads `entry.senderGuild`; `Ingest` persists it to `peerInfo[name].guild`. Existing peerInfo guild values are preserved when an older client (no field 42) broadcasts — only overwritten when the new payload actually carries a value.
- Browser Scanners view: new "Guild" header + per-row column inserted between Name and Contrib. Self-row guild populated live from the API since `peerInfo` never tracks self.

**Stats overview panel**
- New `Stats` button on the inspect frame (below Talents). Opens a side-panel docked to the LEFT of the inspect frame, so a fully-open layout reads: Stats | Inspect | Talents.
- Aggregates `EpogItemCacheDB[id].stats` across the active set's 19 slots. Displays:
  - **Base Stats**: Strength / Agility / Stamina / Intellect / Spirit / Armor (bonus)
  - **Melee**: Damage range (mainhand) / Speed / Power / Hit % / Crit % / Haste % / Expertise %
  - **Ranged**: Power / Hit % / Crit % / Haste %
  - **Spell**: Spell Power / Hit % / Crit % / Haste % / Mana per 5s / Penetration
  - **Defense**: Defense Rating / Dodge % / Parry % / Block % / Block Value / Resilience % / Armor Pen %
- Rating-to-percent conversion uses WotLK level-80 constants (`RATING_PER_PERCENT_L80`). Sub-80 inspects show slightly inflated %s but the relative ordering is correct.
- Stats panel auto-refreshes when switching players (`ShowInspect` calls `SetPlayer` if the panel is open).

---

## EpogArmory v1.4.1 — Test build: aura interlock disabled *(2026-05-05)*

**Internal test version. Patch-level bump means the auto-update notification on the mesh stays silent (`CompareMajorMinor` returns 0 for 1.4.0 → 1.4.1).** No GitHub Release post for this version.

Goal of this build: validate whether the v1.4.0 gear-read settle (400ms) + vanity-flip verify pass (1.5s) is enough on its own to filter out Ascension's transmog visual reads, *without* the `Reality Recalibrators` aura interlock backstop.

- New top-level flag `local REQUIRE_REALITY_AURA = false`. Wraps all three existing interlock points (`BuildPayload`, `ScanRoster`, `TryInspect`) so they only enforce the aura check when `true`. Flipping back to `true` is a one-line revert if data quality regresses.
- Diagnostic surfaces (`/epogarmory status`, `/epogarmory aura`, browser banner, minimap tooltip) now read the flag and accurately describe behavior in test mode — they say "TEST MODE: scanning anyway" rather than "auto-inspect paused", which would be misleading when the gate is off.
- New public API `_G.EpogArmory.RequiresRealityAura()` so the UI module can check the flag without re-importing the constant.

What to watch for during testing:

1. **Gear quality**: do scans without the aura now produce real-gear payloads, or do transmog visuals slip through despite the settle+verify? If transmog leaks, we know the timing-only approach isn't sufficient and the aura gate has to come back.
2. **Mesh pollution**: with the gate off, every aura-less inspect generates a broadcast. If the verify pass detects flips and corrects, the corrected payload eventually wins. But the *initial* broadcast might still be wrong gear. Watch peer scan logs.
3. **Self-scans**: should be unchanged. Self-side never depended on the aura.

To revert: set `REQUIRE_REALITY_AURA = true` in EpogArmory.lua (single line near the `REALITY_AURA_NAME` constant).

---

## EpogArmory v1.4.0 — Inspect reliability + quality gate *(2026-05-05)*

Consolidated release covering the v1.3.1–v1.3.5 iteration cycle. Headline improvements: inspects produce more accurate gear data, partial loadouts no longer pollute the mesh, and the addon no longer leaks frames over a long session.

**Inspect reliability**
- **400ms gear-read settle window** after `INSPECT_TALENT_READY`. Ascension's transmog layer can return cosmetic appearance item IDs for ~290ms after the event fires; the settle delay lets the server resolve real equipped items before we read the slots.
- **+1.5s vanity-flip verify pass** re-reads the inspected unit's slots after the initial broadcast. If transmog flipped any slot non-deterministically post-settle, a corrected payload is broadcast; otherwise no-op.
- **Instance-entry re-inspect**: clears the 15-min in-memory cooldown for all current group members on `PLAYER_ENTERING_WORLD` when in an instance, so every run starts with fresh inspects. The 24h mesh-wide DB gate is preserved for cross-client dedup.

**Data quality**
- **Full-set gear gate** (sender + receiver). New `CheckFullSet` helper rejects any payload missing a "useful" slot — head, neck, shoulder, chest, waist, legs, feet, wrist, hands, both rings, both trinkets, back, mainhand, ranged/relic. Slot 17 (offhand) is conditionally required only when slot 16 isn't a 2H weapon. Slot 4 (shirt) and 19 (tabard) are disregarded as cosmetic. Catches mid-equipment-swap inspects that previously polluted the DB with weapon-less loadouts.

**Stability**
- **Frame leak elimination**: `OnInspectReady` was allocating a fresh `CreateFrame("Frame")` per settle and per verify pass; WoW frames are never garbage-collected, so a 25-man raid scanned every 4h was leaking ~150 frames/day per client. Hoisted to two module-level recyclable frames.
- **Talent panel build-once-cache**: `EpogArmory_OpenTalentsFor` previously destroyed and rebuilt the talent frame on every open, leaking ~180 child objects per click and growing `UISpecialFrames` unbounded. Switched to single-cached frame with `SetPlayer`/`RenderTab` clearing prior state.
- **Talent grid visual fixes**: 9-tier rows (was capped at 7, missing TBC content), `CreateFrame("Frame")` cells with explicit `EnableMouse(true)` (Button hit-testing was eating OnEnter on 3.3.5), `CreateTexture`-based per-cell backgrounds (replaced `SetBackdrop` which silently aborted the render loop), corrected slot draw-layer ordering.

**Codebase audit**
- Two parallel agents reviewed all 5,660 lines (`EpogArmory.lua` + `EpogArmoryUI.lua`) for Lua 5.1 / WoW 3.3.5 incompatibilities, memory leaks, hot-path perf issues, and SavedVariables corruption risks. Confirmed clean: no `xpcall` extra-arg misuse, no `C_Timer`, no `bit32`, no `goto`, no `\z`, no modern `C_AddOns`/`Settings.*`/`MenuUtil`/`CreateFromMixins` anywhere; forward-compat wire format with `t[N] or default` everywhere; tooltip ownership properly defended against pfQuest/Leatrix theft.

**Backward compatibility**
- Wire format unchanged since v1.3.0 (talent ranks at position 41). All earlier versions parse cleanly.
- `MigratePlayers` continues to handle pre-v0.13 flat entries and v0.13+ unkeyed sets.
- `ShouldStore` quality gate runs only on incoming broadcasts — pre-existing DB entries (including any legacy partial loadouts) survive intact.
- No cache-wipe on update. Accumulated mesh data is preserved across all future addon upgrades; the experimental `DB_SCHEMA_VERSION` wipe added mid-cycle was reverted.

---

## EpogArmory v1.3.5 — Remove schema-version cache wipe *(2026-05-05)*
Reverts the `DB_SCHEMA_VERSION` wipe logic that was added in v1.3.2. The original idea was to drop stale cache entries on shape-breaking addon updates, but the tradeoff was wrong: throwing away the user's accumulated mesh data on every bump is a significantly worse outcome than the hypothetical "stale shape might mis-render" scenario. The wire format is already forward-compat (every receiver does `t[N] or default` for trailing fields), and any genuine on-disk shape change should be handled with a per-field migration in the read path — not a full wipe.

- Removed the `DB_SCHEMA_VERSION` constant from the top of the file.
- Removed the `storedSchema < DB_SCHEMA_VERSION` check + wipe block from `PLAYER_LOGIN`.
- Removed the orphaned `EpogArmoryDB.meta = EpogArmoryDB.meta or {...}` defensive init that was only there to give the wipe block a stable place to write the schema field.
- The `meta` field still gets initialized via the top-level `EpogArmoryDB or {...}` fallback, just no longer referenced for migration decisions.

---

## EpogArmory v1.3.4 — Audit fixes: frame-leak elimination *(2026-05-04)*
Codebase audit findings, three real bugs fixed:

- **Per-inspect frame leaks (`OnInspectReady`)**: each inspect was calling `CreateFrame("Frame")` for both the settle timer and the verify timer. WoW frames are never garbage-collected — they live forever in the C-side frame registry. In a 25-man raid scanned every 4 hours, that was ~150 leaked frames/day per client. Hoisted to two module-level recyclable frames (`INSPECT_SETTLE_FRAME`, `INSPECT_VERIFY_FRAME`); each new inspect just re-assigns `OnUpdate` instead of allocating. Per-call closures still capture their own `snapUnit/snapGuid/elapsed` locals, so reuse is safe. Settle is naturally serialized via `current`; verify can be clobbered by a back-to-back inspect within 1.5s, which silently skips the older verify (acceptable — initial broadcast already went out).
- **Talent frame destroy+rebuild leak**: `EpogArmory_OpenTalentsFor` was destroying and rebuilding the talent frame on every open, leaking ~180 child objects per click and growing `UISpecialFrames` unbounded. Switched to build-once-cache: `BuildTalentFrame` runs only on first open, subsequent opens just call `SetPlayer` (which already clears prior spec state via `RenderTab`). One-time `tinsert(UISpecialFrames, "EpogArmoryTalentFrame")` now only fires once.
- **`subLevel` arg on `CreateTexture` (UI:685)**: arrow pool used `t:CreateTexture(nil, "ARTWORK", nil, 1)` — the 4th `subLevel` argument is silently dropped on WoW 3.3.5, leaving arrows on the default ARTWORK sublevel where they could render behind icon cells. Removed the unsupported args.

**Audited and confirmed clean** (selected): no `xpcall` extra-arg misuse; no `C_Timer`, `bit32`, `goto`, `\z`, or `//`; no modern `C_AddOns`/`Settings.*`/`MenuUtil`/`CreateFromMixins` usage anywhere; forward-compat wire format with `t[N] or default` everywhere; schema-version wipe correctly preserves `config`/`peerInfo`/`knownChars`; instance-entry `seen[]` reset preserves `lastScanned[]` for mesh dedup; `CheckFullSet`/`IsTwoHandRef` slot numbering matches WoW INVSLOT; closures in `OnInspectReady` capture snapshot vars correctly and re-validate after both delays; `outQueue`/`inQueue`/`seen`/`assembly` all bounded by their respective TTL/cleanup paths.

---

## EpogArmory v1.3.3 — Full-set gear gate *(2026-05-04)*
Reject incomplete loadouts caused by mid-equipment-swap inspects, where the player has briefly unequipped a weapon (or other slot) and the inspect happens during the gap.

- **New `CheckFullSet(gearLookup)` helper** alongside `ItemStringFromLink`. Verifies every "useful" slot is filled. Required slots: head, neck, shoulder, chest, waist, legs, feet, wrist, hands, both rings, both trinkets, back, mainhand, ranged/relic. Slot 17 (offhand) is **conditionally** required — only when slot 16 isn't an `INVTYPE_2HWEAPON`. Slot 4 (shirt) and slot 19 (tabard) are intentionally disregarded.
- **Sender side (`BuildPayload`)**: replaces the old `equipped < 10` numeric floor. If any required slot is empty, returns `nil, "missing <slotname> (slot N) (likely mid-swap, retry)"` — short-retry path picks the player up again with their full kit equipped.
- **Receiver side (`ShouldStore`)**: same gate, mirrored — refuses to persist any incoming broadcast that fails the full-set check, even from older addon versions or buggy peers.
- **`IsTwoHandRef` helper** tolerates both link form (sender side) and item-string form (receiver side from `entry.gear[slot]`). Conservative on unknown items: treats unresolved `GetItemInfo` as "not 2H" so unverifiable mainhands force the offhand requirement.
- Removed orphaned `MIN_STORE_EQUIPPED` constant (replaced by the per-slot gate).

---

## EpogArmory v1.3.2 — Inspect reliability improvements *(2026-05-04)*
Inspect-quality improvements targeting Ascension's transmog/vanity layer and stale-cache problems:

- **400ms gear-read settle window**: `OnInspectReady` now defers `BuildPayload` by 400ms after `INSPECT_TALENT_READY` via a one-shot `OnUpdate` frame timer. Ascension's transmog layer can return cosmetic appearance item IDs for ~290ms after the event fires; the settle window lets the server resolve real equipped items before we read the slots. `current` stays set during the wait (naturally blocking new inspects), and the callback re-validates both `current.guid` and `UnitGUID(unit)` before reading, so a `CheckTimeout` clearing the slot mid-settle discards the result safely.

- **Vanity-flip verify pass**: after the initial broadcast, `OnInspectReady` snapshots the slot fingerprint and re-reads the unit at +1.5s. If any slot's item link changed (transmog flipped non-deterministically post-settle), it rebuilds the payload and broadcasts the corrected version. New helper `InspectSlotFingerprint(unit)` concatenates 19 slot item-strings; receivers' existing dedup absorbs no-op cases. Re-broadcast only fires when fingerprints actually diverge.

- **Instance-entry re-inspect**: `PLAYER_ENTERING_WORLD` now clears `seen[guid]` for all current raid/party members when `IsInInstance()` is true. This bypasses the 15-minute in-memory cooldown so every group member is re-queued for a fresh scan at the start of each instance. The 24-hour `EpogArmoryDB.lastScanned` gate is intentionally preserved so mesh-wide dedup still works across all clients.

- **Schema-version cache wipe**: new `DB_SCHEMA_VERSION = 1` constant (paralleling `CACHE_SCHEMA` for `EpogItemCacheDB`). On `PLAYER_LOGIN`, if `EpogArmoryDB.meta.schemaVersion` is missing or lower than the constant, `players[]` and `lastScanned[]` are wiped — `config`, `peerInfo`, `knownChars` are preserved. Bumping this constant in future wire-format-breaking changes will auto-clean stale entries that would otherwise corrupt new renders. Today's wipe is silent (no prior schemaVersion stored = first-run baseline); a real bump prints a yellow chat notice with the wipe count.

**Not implemented (with rationale):**
- *FNV-1a content-hash dedup* — already covered by `SelfFingerprint` (concatenated item-strings + level + spec), which is functionally equivalent. A 32-bit hash would save a few hundred bytes of memory but no observable wall-clock difference; not worth the regression risk.
- *Boss-transition re-inspect* — needs raid-context hooks (encounter start/end detection) that aren't present yet on the client. Will revisit when raid-aware features land.

---

## EpogArmory v1.3.1 — Talent tree visual fixes *(2026-04-30)*
Three visual bugs fixed in the in-game talent tree panel (`BuildTalentFrame`):
- **Icon behind border**: icon texture layer changed from `BORDER` → `ARTWORK`. Draw order is BORDER → ARTWORK → OVERLAY, so the icon now renders above any per-button background but the OVERLAY slot border still frames it correctly.
- **Background completely off**: replaced 4-quadrant tile approach (`bgTL/TR/BL/BR` with `-TopLeft`/`-TopRight` etc. suffixes) with a single `t.bgTexture` covering the full grid area. WotLK 3.3.5 uses a single texture per spec (`Interface\TalentFrame\<base>`), not quadrant tiles.
- **Scaling off (rank badge)**: removed `rankBG` diamond texture (`TalentFrame-RankBorder`) which was over-sized and misplaced. Rank text is now a plain `GameFontNormal` FontString anchored to the button's `BOTTOMRIGHT` corner with a drop shadow — readable on any background.

---

## LootAppraiser-3.3.5 v1.19 — Restore Esc-to-close without persisting hidden state *(2026-05-17)*
- Put the frame back in `UISpecialFrames` (so Esc closes it just like v1.16 and earlier), but wrap `CloseSpecialWindows` globally to set `LA._inCloseSpecialWindows = true` for the duration of the iteration. The `OnHide` hook then skips its `windowShown = false` persistence whenever the flag is set — so Esc-closes, death/spirit-release popup dismissals, instance-entry confirmations, etc., all hide the window for the current session but `/reload` brings it back. Only the **Hide** button on the frame persists hidden state (it's the one user-driven Hide() path outside the CloseSpecialWindows wrapper).
- Function-replacement on `CloseSpecialWindows` is intentional. `hooksecurefunc` only post-hooks, which would fire after the OnHide we want to gate.

---

## LootAppraiser-3.3.5 v1.18 — Stop hiding on death / instance entry *(2026-05-16)*
- Removed the frame from `UISpecialFrames`. WoW's `CloseSpecialWindows()` iterates that list and hides every entry — and it's called from more than the Esc key (some popup dismissals on death/spirit-release/instance-entry trigger it). Combined with v1.17's persistent visibility, each of those events silently flipped `windowShown` to `false` and persisted it. Trade-off: **Esc no longer closes the window** — use the Hide button, `/la`, or `/la toggle`.

---

## LootAppraiser-3.3.5 v1.17 — Window visibility persists across reload/login *(2026-05-16)*
- Removed the unconditional `LootAppraiserFrame:Hide()` from `PLAYER_LOGIN`. New profile field `windowShown` (default `false`) is read in `UI.Build()` to apply the initial state, with `OnShow` / `OnHide` hooks keeping it in sync for the rest of the session. Net: open it once, leave it open — reload/logout/login keeps the window in the same state, same position, same size.

---

## LootAppraiser-3.3.5 v1.16 — Item level in loot rows *(2026-05-11)*
- Loot rows now show item level next to the name in muted grey, e.g. `Traveler's Spaulders (40)  [de]   3g 4s`. Captured once in `BuildEntry` (`entry.ilvl = select(4, GetItemInfo(link))`) and rendered in `RefreshList`. Items where `GetItemInfo` was still cold at ingest get `ilvl = 0` and the suffix is hidden.
- Useful for telling apart same-named items across level brackets — WoW has many duplicate-named items (Traveler's, Robust, Resilient) with different itemIDs that resolve to different pricing branches (one BoP → `[de]`, one BoE → `[v]`).

---

## LootAppraiser-3.3.5 v1.15 — Crafted items don't add to session value *(2026-05-04)*
- **Removed `LOOT_ITEM_CREATED_SELF*` from `LOOT_PATTERNS`.** Crafted items aren't real loot — they're transformations of gathered mats, and counting them visually double-up alongside the mats they consumed. Crafted items no longer appear as session rows.
- **New `CRAFT_PATTERNS` matched separately** in `HandleChatMsgLoot`. A `"You create:"` chat line sets `craftingWindowUntil = GetTime() + 0.7`.
- **`ReconcileBags` skipped during the craft window.** Otherwise the BAG_UPDATEs for ingredient consumption would debit the already-counted gathered mats, making session value drop on crafting. `pendingReconcile` still resets each skipped pass so future (post-window) bag changes reconcile normally.
- **Net effect**: loot 12 Runecloth → session shows 12g. Craft a bandage (consumes 5 Runecloth + 1 Silk) → no bandage row added, mats not debited, session value stays at 12g. Destroy/vendor/mail outside the craft window still reconcile.

---

## LootAppraiser-3.3.5 v1.14 — Vertical resize via bottom-right grip *(2026-05-04)*
- **Drag the bottom-right corner to grow the row count** (not scale). `frame:SetResizable(true)` + `SetMinResize/SetMaxResize` with width pinned to `WINDOW_W` so only height moves. Blizzard chat-style size grabber (`Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-*`) at the corner; `StartSizing("BOTTOMRIGHT")` on mousedown, `StopMovingOrSizing` on mouseup.
- **`OnSizeChanged` recomputes `MAX_ROWS`** every drag tick and lazily builds new row widgets via `BuildRow(content, idx)` (cheap: one font string per row, only when needed). Mouseup snaps height to an exact multiple of `ROW_H` so rows never half-clip, and persists `windowPos.h` alongside the existing point/x/y.
- **Shrink also works:** `RefreshList` now iterates the full `#rows` (not `MAX_ROWS`) and hides any rows beyond the current `MAX_ROWS`.
- **Saved-size restore:** `Build()` invokes `OnSizeChanged` once manually at the end so a saved height > default populates the extra row widgets cleanly before the first `FullRefresh`.

---

## LootAppraiser-3.3.5 v1.13 — Single-line header + button-fit width + 8-row scroll *(2026-05-03)*
- **Single-line header**: `Zone · M:SS · TotalValue · GPH/h · Nx`. Total field now displays `lootTotal + goldDelta`, so coin drops and vendor sales are reflected in the session total alongside item-loot value (no double-count — `lootTotal` and `goldDelta` are independent streams).
- **Width fits exactly 4 buttons**: WINDOW_W 290→248 (`6 + 56*4 + 4*3 + 6`). No more dead space.
- **8 visible rows** (was 14) with FauxScrollFrame scrollbar appearing past row 8. Row layout switched from fixed name-width to anchor-to-anchor so names truncate gracefully (`SetWordWrap(false)`).
- Total window: 226 → 136 px tall, ~40% smaller area than v1.12.

---

## LootAppraiser-3.3.5 v1.12 — Compact UI + persistent window position *(2026-05-03)*
- **Compact layout.** Dropped the big "Loot Appraiser" title and zone subtitle for a two-line summary header (`Zone  Time  GPH/h` / `Total  · N items`) with inline colour coding. Window dimensions: 320→290 wide, 288→226 tall (~21% smaller). Row height 14→12, visible rows 12→14, footer buttons 60×20→56×18.
- **Window position remembered.** New `LootAppraiserDB.profile.windowPos = {point, x, y}` saved on drag-stop and restored in `UI.Build()`. Falls back to `CENTER, 0, 0` when nil. `SetClampedToScreen` keeps the frame on-screen after resolution changes.

---

## LootAppraiser-3.3.5 v1.11 — `/la dump` + stack-aware loot patterns *(2026-05-03)*
- **Stack support for Ascension wins.** The custom `"You won: …"` format wasn't capturing stack counts — looting 5 Runecloth via group greed ingested as a single. Added a stack-aware variant `"^You won: (.+)x(%d+)$"` placed *before* the single-item `"^You won: (.+)$"` so Lua's first-match semantics catches the count. Same ordering fix applied to the Blizzard `_MULTIPLE` patterns (now precede their single counterparts).
- **`/la dump <link>`** comprehensive single-item diagnostic. Replaces v1.8's `/la price` (kept as alias). Five sections: Identity (link, itemKey, isBoP, GetItemInfo basics), ArkInventory (cache key, raw catID, decoded type/code, global name, bag-scan slot.cat fallback, resolver result), Config (live profile values for all four pricing options + quality floors), Pricing (AH, DE, vendor + final decision), Session (zone, total, GPH, matching rows with count/unit/value/src/age, bag-tracking ledger via new `Session.GetBagLedger`), plus current bag location.

---

## LootAppraiser-3.3.5 v1.10 — Ascension custom loot patterns + rule-based categories *(2026-05-03)*
- **Catch Need/Greed wins on Ascension.** Verbose trace exposed Ascension's modified server emitting `"You won: [Item]"` on `CHAT_MSG_LOOT` instead of retail's `"You receive loot: [Item]."`. Added a literal Lua pattern `^You won: (.+)$` to `LOOT_PATTERNS`.
- **Rule-classified ArkInventory categories.** Old lookup only checked `db.profile.option.category[key]` (manual drag-and-drop). Added `GetArkInvCategoryNameFromBags(itemID)` that walks `ArkInventory.db.realm.player.data[me].location[Bag].bag[*].slot[*]` and resolves `slot.cat` to a name — that's where ArkInventory's rule engine stamps category IDs during its bag scan. Full lookup chain now: explicit assignment → bag-scan fallback → "default".
- **Re-price recent vendor rows on `BAG_UPDATE`.** Fresh greed-wins have a timing race — `CHAT_MSG_LOOT` fires before ArkInventory's bag scan runs, so a rule-classified item resolves as `default` → vendor on first ingest. New `Session.RepriceRecentVendor()` runs on the same debounced reconcile tick (300ms after `BAG_UPDATE`), walks rows newest-first up to 5 seconds back, and promotes any vendor row to AH/DE if the new pricing resolves there. Self-stabilising via the `if row.src == VENDOR` guard.

---

## LootAppraiser-3.3.5 v1.9 — `/la verbose` for loot-pipeline diagnostics *(2026-05-02)*
Added `/la verbose` toggle that prints every `CHAT_MSG_LOOT` raw line, whether `ParseChatLoot` matched, and the full `IngestLoot` decision tree (quality, keep flag, unit/src, drop reasons or success). Used to diagnose category-routing issues — exposed Ascension's custom `"You won:"` chat-loot format that v1.10 then catches.

---

## LootAppraiser-3.3.5 v1.8 — `/la price` debug trace *(2026-05-02)*
Added `/la price <link>` to dump the full pricing trace for a single item: itemID/itemKey/isBoP, ArkInventory cache key, raw `type!code` stored value, resolved name, active config strings, AH/DE/vendor source values, and the final `(copper, source, isBoP)` decision. Usage: type `/la price ` then shift-click an item from bag. Used for diagnosing items in Value/Trash categories that aren't surfacing as expected.

---

## LootAppraiser-3.3.5 v1.7 — Need/Greed wins are tracked again *(2026-05-02)*
Removed the v1.2 "loot window recently open" gate on `LOOT_ITEM_SELF`. The gate was meant to keep group-roll deliveries out of the session but was over-aggressive: greed-wins fire `LOOT_ITEM_SELF` *without* opening a loot window, so items the player genuinely received via Need/Greed never reached `IngestLoot`. Trust `LOOT_ITEM_SELF` unconditionally now — it only fires when the item enters your bags, regardless of source. Other players' wins still ignored (they fire `LOOT_ITEM`, intentionally absent from our patterns); peeking at mob loot still ignored (no chat-loot delivery line for just opening the frame). LOOT_OPENED/LOOT_CLOSED registrations dropped — gate state was their only consumer.

---

## LootAppraiser-3.3.5 v1.6 — Consume category routes to AH pricing *(2026-05-02)*
- `arkInvValueCategory` default expanded from `"Value"` to `"Value,Consume"`. Items in a `Consume` custom category (potions, food, reagents) go through the AH chain. The comma-separated list support already plumbed through `CatNameInList` since v1.4 — just plugged the second name in.
- Migration 1.5 → 1.6: existing installs on `"Value"` auto-rewritten to `"Value,Consume"`. Customised values untouched.

---

## LootAppraiser-3.3.5 v1.5 — Catch uncategorised items via System "Default" *(2026-05-02)*
The v1.4 vendor override only matched manually-dragged custom categories; uncategorised items (most of a typical loot stream) silently bypassed it and fell through to the AH chain. Fixed by returning `"default"` from `GetArkInvCategoryName` when no explicit assignment exists, and bumping the default `arkInvVendorCategory` to `"Junk,Trash,Default"`. Existing installs on the v1.4 default are auto-migrated; customised values are left alone. Workflow: tag profitable items into `Value` (→ AH), DE-able items into `DE` (→ disenchant), leave the rest uncategorised (→ vendor).

---

## LootAppraiser-3.3.5 v1.4 — Junk/Trash vendor override + 0c filter + disenchant fix *(2026-05-02)*
- **Junk/Trash vendor override:** new ArkInventory-category list (default `"Junk,Trash"`). Items the user assigns to any of these categories are forced to vendor pricing, bypassing any incidental AH listing. `/la vendorcat <comma-list>`. All three category configs (Value/DE/Vendor) now accept comma-separated lists.
- **Zero-copper rows dropped from the list** (`skipZeroValueRows`, default on). Items priced at 0c (vendor-0 quest items, low-tier reagents, vendor trash) no longer pollute the row list. Toggle via `/la skipzero`.
- **Disenchant double-counting fix.** Two bugs:
  1. `Session.ReconcileBags()` was modifying `state.bagOwn` while iterating it via `pairs()` — undefined in Lua 5.1; entries were silently skipped per pass, which surfaced as the disenchanted source item lingering in the row list while the produced mats also appeared. Rewrote to materialise IDs first, mutate second.
  2. Added `UNIT_SPELLCAST_SUCCEEDED` hook for `player` casts of Disenchant (13262), Milling (51005), and Prospecting (31252). Forces a reconcile pass on cast — these spells consume an item and produce mats in a single client tick, so hooking the spell directly is the most robust signal even with the pairs-iteration fix in place.

---

## LootAppraiser-3.3.5 v1.3 — Bag reconciliation (deleted/sold items leave the session) *(2026-05-02)*
- **`Session.Start()`** now snapshots current bag contents into a per-itemID **baseline**, and `Session.AddLoot()` keeps a parallel **`bagOwn`** ledger of session intake.
- **`BAG_UPDATE`** is hooked in `Core/LootManager.lua` (debounced 0.3s after the last in a burst) and triggers **`Session.ReconcileBags()`**. The pass re-scans bags and debits any per-itemID loss against `bagOwn` first, falling back to the baseline only if the entire session-tracked amount is already gone.
- **`ApplyLossToLootRows()`** walks `lootRows` newest-first (LIFO), decrementing or removing rows until the loss is satisfied. Partial losses reduce a row's count and value proportionally; depleted rows are removed.
- Net effect: destroying / vendoring / mailing / trading loot during a session correctly drops `lootTotal` and `itemCount`, and the GPH recalculates on the next refresh tick. No double-count against `GoldDelta` because the two streams are independent (vendoring drops `lootTotal` while `GoldDelta` rises by the sale amount; destroying drops `lootTotal` and leaves `GoldDelta` flat).

---

## LootAppraiser-3.3.5 v1.2 — Real-loot-only detection + quality migration *(2026-05-02)*
- **Loot detection switched from `LOOT_OPENED` to gated `CHAT_MSG_LOOT`.** Peeking at a mob's loot table no longer counts items as looted, and re-opening the same corpse no longer creates duplicate rows. Now only items that actually land in your bags are tracked: `LOOT_ITEM_SELF` / `LOOT_ITEM_SELF_MULTIPLE` lines, gated on a "loot window was recently open" flag set by `LOOT_OPENED` and cleared 500ms after `LOOT_CLOSED`. Need/Greed roll deliveries (which fire `LOOT_ITEM_SELF` without ever opening a loot window) stay excluded. Crafted-item lines (`LOOT_ITEM_CREATED_SELF`) bypass the gate since crafting has no loot frame. Recent-seen dedup buffer removed — with one event source there's nothing to dedup against.
- **One-shot DB migration** keyed off `LootAppraiserDB._dbVersion`: existing installs with v1.0's saved `minQuality=2` are auto-reset to `minQuality=0` on first v1.2 launch, so whites/greys finally show without manual `/la quality 0`.

---

## LootAppraiser-3.3.5 v1.1 — Whites/greys + ArkInventory category overrides *(2026-04-30)*
- **Strict personal-loot mode:** only items you click-loot from corpses (autoloot or manual via `LOOT_OPENED`) plus items you craft (`LOOT_ITEM_CREATED_SELF`) are tracked. Group-loot deliveries (Need/Greed wins, others' wins) are ignored — including your own roll wins. The `showGroupLoot` option / `/la group` command were removed.
- **Default quality threshold lowered to 0** (poor) so greys and whites are tracked alongside greens+. Existing installs keep their saved value; use `/la quality 0` to switch.
- **ArkInventory custom-category overrides** (`Core/Pricing.lua`): items the user has manually assigned to a category named `Value` are force-priced through the Aux/TSM AH chain; items in a category named `DE` are priced as their disenchant expected value via TSM2's enchanting yield tables. Names configurable via `/la valuecat <name>` and `/la decat <name>` (set to empty string to disable). Lookup walks `ArkInventory.db.profile.option.category["item:<id>:<sb>"]` then `db.global.option.category[type].data[code].name`. No-op if ArkInventory isn't loaded. Both overrides fall through to the default chain when they can't produce a price.

---

## LootAppraiser-3.3.5 v1.0 — New addon *(2026-04-30)*
A live loot tracker with gold-per-hour, AH value, vendor and disenchant pricing. Inspired by ProfitzTV's *LootAppraiser* (TWW retail), rewritten from scratch for 3.3.5 + Ascension's unified cross-faction AH. ~1,100 lines of Lua across 6 source files.

- **Pricing chain:** Aux merged AH price (cross-faction) → TSM2 `DBMarket` → DE expected value (via TSM2's enchanting yield tables, materials priced through the same chain) → vendor sell. Source tag shown per row (`[ah]` / `[tsm]` / `[de]` / `[v]`).
- **Loot detection:** `LOOT_OPENED` for solo (autoloot or manual), `CHAT_MSG_LOOT` for group loot and self-create (crafting). Self-loot patterns deliberately skipped from the chat path so solo loot isn't double-counted.
- **Session state machine:** Start / Stop / Pause / Resume / Reset, with paused time excluded from GPH. Single session per game session by design.
- **UI:** movable frame with live header (Time / GPH / Total / Items + zone), 12-row scrolling loot list with quality colours and tooltip on hover, Shift+Click to chat-link, Ctrl+Click to dressing-room-preview, Esc to hide.
- **Slash commands:** `/la` toggles. Sub-commands: `start`, `stop`, `pause`, `resume`, `reset`, `de`, `group`, `soulbound`, `quality <0-7>`, `wipecache`, `help`.
- **Cache invalidation:** AH price cache wipes on `AUCTION_HOUSE_CLOSED` so a fresh Aux scan flows through immediately. DE values share the cache (they reference AH prices) so they invalidate together.
- **SavedVariables:** `LootAppraiserDB.profile` — minQuality, useDisenchant, showGroupLoot, ignoreSoulbound, autoStart, showOnLoot.

Files: `LootAppraiser-3.3.5.toc` / `LootAppraiser-3.3.5.lua` / `Core/{Const,Pricing,Session,LootManager}.lua` / `UI/Window.lua` / `CHANGELOG.md`.

---

## Aux-addon v1.4 — Smoother AH scanning on large AHs *(2026-04-24)*
On dense servers (600+ AH pages, ~30k auctions) the search scan became progressively slower and chewed increasing memory. Root cause: `search.table:SetDatabase()` was called after every page via `on_page_scanned`, and that goes through `UpdateRowInfo` which does an `O(N log N)` sort plus an `O(N)` grouping pass over `search.records`. At 600 pages × 30000 records that's ~260 million comparisons during one scan.

Two changes in `tabs/search/results.lua` and `tabs/search/frame.lua`:

- **Throttle mid-scan refresh (always on, no UI change):** `on_page_scanned` now skips the live table rebuild once `getn(search.records) > LIVE_REFRESH_MAX_RECORDS` (2000). `on_complete` does one guaranteed final `SetDatabase` so the full result set still renders when the scan finishes. Small searches (under 2k results) still refresh every page for responsive feel.
- **New "Bg" (background scan) toggle button** next to Resume/Pause: when active, `on_auction` skips `tinsert(search.records, ...)` entirely. The scan still walks every page and `history.process_auction()` in `core/scan.lua` still records all prices — only the result table is suppressed. Memory stays flat regardless of AH size. Ideal for nightly full-AH price sweeps. State persists in `aux.account.background_scan` (same scope as `history_decay`).
- **Status bar text in background mode** shows `[bg, N prices processed]` during the scan and `Scan complete (background, N prices processed)` at the end so the user sees the work is happening.

---

## EpogArmory v1.3.0 — Per-talent rank capture + in-game talent tree *(2026-05-03)*

Capture full talent point distribution per scan, not just per-tab totals. Renders an in-game talent tree side-panel on the inspect frame and seeds the data for an interactive web renderer on epoglogs.com.

### What we capture now

Previously each scan stored only the per-tab totals (`spec = {19, 42, 0}` — 19 in tab 1, 42 in tab 2, 0 in tab 3). That's enough to compute the dominant tree but loses everything about *which* talents have ranks.

Now `BuildTalentRanks` iterates `GetTalentInfo` for every talent in every tab, capturing the spent rank in talent-index order:

```
"0,0,5,3,0,0,5,5,5,5,3,0,0,5,5,3;0,0,0;0,0,0"
   tab 1 ranks per talent     ; tab 2 ; tab 3
```

### Wire format

Position 41 (additive after position 40 item-hints from v1.2). Backward compatible — pre-v1.3 receivers ignore the unknown trailing field. Mixed-version mesh works fine; full benefit when sender + receiver are both on v1.3+.

Wire size: ~150-250 bytes per scan (3 tabs × ~30 talents × 1-2 chars per rank + delimiters). Tiny next to the v1.2 item-hints (~2KB).

### Storage

Each set on a stored player record gains a `talentRanks` field:

```lua
EpogArmoryDB.players[guid].sets[group] = {
    spec        = { 19, 42, 0 },
    talentRanks = {
        [1] = { 0, 0, 5, 3, 0, 0, 5, 5, 5, 5, 3, 0, 0, 5, 5, 3 },
        [2] = { 0, 0, 0 },
        [3] = { 0, 0, 0 },
    },
    ...
}
```

Indices are stable per class on a given Ascension build — the website maps talent index → name/tier/column via class talent tree metadata extracted from DBC by `epog-data`.

### Self-scans + inspect-scans both capture

`BuildTalentRanks(unit)` works for `"player"` and inspected units alike. Self-scans on relog / respec / gear change get talent ranks. Inspect scans of groupmates get them too (uses `isInspect=1` in `GetTalentInfo` calls, same pattern as the existing `ReadSpecPoints`).

### Talent metadata capture (new SavedVariable: `EpogTalentTreeDB`)

The wire only carries ranks (small) — full metadata (talent name, icon, tier, column, maxRank per talent, ~30 talents × 3 tabs = 90 entries × ~200 bytes = ~18 KB) is way too big to ship per scan. Instead, each client builds up its own metadata DB by observing scans:

- Self-scans always populate metadata for the player's own class
- Inspect-scans populate metadata for the inspected player's class (using `GetTalentInfo` with `isInspect=1` — same as how Blizzard's inspect UI gets the data)

`EpogTalentTreeDB[classFile] = { tabs = { [1] = { name, icon, talents = { [i] = {name, icon, tier, column, maxRank} } }, [2] = ..., [3] = ... }, lastUpdate = unixTs }`

Account-wide SavedVariable. As the user scans varied classes over time, metadata accumulates automatically.

### In-game talent tree renderer

New "Talents" button on the inspect frame, below Back / Delete. Opens a 210×388 side-panel anchored to the right of the inspect frame.

- 3 spec tabs across the top (named per the player's actual tree names — `Holy`, `Discipline`, `Shadow`, etc.)
- 4-column × 7-tier talent grid (matches Blizzard's standard layout)
- Each cell renders the talent's icon (full color when learned, desaturated when not), with rank overlay `N/maxRank` in the corner — green when maxed, yellow when partial, gray when 0
- Hover for tooltip with talent name + rank
- Defaults to the player's dominant tree on open
- Subtitle shows `<TabName> N points`
- Re-renders when the inspect frame switches to a different player or set
- Hides automatically when Back returns to the browser

If `EpogTalentTreeDB` lacks metadata for the displayed class+tab, the panel shows a clear "no metadata yet — scan a [Class] with the Reality Recalibrators aura to populate" message instead of an empty grid.

### What's left for the website

- `epogarmory-web` reads `talentRanks` from uploaded SavedVariables
- Renders an interactive talent tree using `EpogTalentTreeDB` metadata (uploaded alongside the player DB) or `epog-data` class definitions
- Hover for tooltip with description + rank progression
- Per-set permalink

Web side is a separate session's work on `C:\Dev\epogarmory-web`.

### No protocol changes for existing fields

Wire positions 1–40 unchanged. Position 41 is purely additive.

---

## EpogArmory v1.2.0 — Reality Recalibrators gating + scanner item hints *(2026-04-29)*

Two big additions on top of v1.1, plus all the v1.1.x patch refinements rolled in.

### 1. Reality Recalibrators aura gating

Ascension's transmog system overrides what `GetInventoryItemLink` returns for inspected players — without an in-game aura, you see the player's *visual* itemID (often "naked" or low-level cosmetic), not the real gameplay item. The addon was happily scanning these and polluting the mesh with junk.

The **Reality Recalibrators** aura grants a server-side override that makes inspect APIs return true gear. Auto-inspect now requires the aura.

**Three layers of gating:**

- `ScanRoster` — bails before queueing any non-self unit when aura missing. Shows a helpful one-time chat hint when groupmates are present.
- `TryInspect` — defensive recheck right before `NotifyInspect`; drains the queue if the aura wore off mid-cycle.
- `BuildPayload` — final gate; returns nil for non-self units when aura missing.

**Self-scans pass through** — you always see your own real gear regardless of transmog.

**Smart settle window:** zone transitions (BG exit, instance load, login) briefly clear `UnitBuff` from the API's perspective for ~3-6 seconds before the server restores auras. New 10s settle window after `PLAYER_ENTERING_WORLD` skips aura-missing actions silently — no chat nag, no queue drain — until auras settle. Prevents false-positive hints during normal gameplay.

**Visibility everywhere:**
- **Browser frame:** prominent banner under the title shows ✓/✗ aura status with explanation. Updates on show + every 30s tick.
- **Minimap tooltip:** hovering the shield button shows aura status as the first line.
- **`/epogarmory status`:** includes a green/red aura status line.
- **`/epogarmory aura`:** new dedicated status command that also resets the one-time hint flag.

### 2. Scanner-side item-info hints (wire position 40)

Ascension reassigns vanilla itemIDs server-side and modifies stats — receivers can't always resolve item info via local `GetItemInfo` or `CMSG_ITEM_QUERY_SINGLE`. But the **scanner** has correct data right after a fresh inspect (the `SMSG_INSPECT_RESULTS` response populates their dynamic cache).

Scanners now piggyback that data on the gear broadcast at wire position 40:

```
iid~name~q~ilvl~equipLoc~icon~stats;...
```

Receivers seed `EpogItemCacheDB` from the hints with `verified = true, fromHint = true`. Locally-fetched verified entries take precedence over hints (we trust our own server-query result over a peer's claim).

Wire size grew ~3x (from ~700 bytes to ~2.5 KB per scan), but it's the only way to deliver server-correct stats and names for Ascension custom items. Backward compatible — old senders skip position 40, old receivers ignore unknown trailing fields.

### 3. Cache verification (CACHE_SCHEMA v10 → v11)

Slot-vs-equipLoc verification detects the "boots in cloak slot" reassignment cases:

- New `EXPECTED_INVTYPE_BY_SLOT` map covers all 19 slots
- Cache entries gain `equipLoc`, `verified`, `verifyAttempts`, `lastVerifyAt` fields
- Mismatch triggers `SetHyperlink` to refresh the dynamic cache; capped at 3 attempts
- Verified entries short-circuit on next observation — zero overhead

Fixed in v1.1.4 with critical anti-spam: `TryCachePending` no longer re-fires `TriggerItemFetch` on every retry tick (was 4750 SetHyperlinks/sec for 1188-pending caches), and pending-fetches now use the full itemstring (not bare itemID).

### 4. New `/epogarmory dump` command

Forensic per-slot diagnostic. For each set of a stored player, prints:

- Raw itemstring + Ascension-extra-fields detection
- `GetItemInfo(itemID)` and `GetItemInfo(fullLink)` (flagged if they differ)
- `GetItemStats(fullLink)` complete stat dump
- Cache entry contents (with ✓verified / ✗unverified annotation)
- **PvP detection trace** per set: shows trinket name resolution, pattern match result, live verdict, and a MISMATCH warning when stored set group disagrees with live evaluation

### 5. Polish + smaller fixes

- Broader PvP trinket detection — pattern set now `{ "Insignia", "Medallion", "Battlemaster's" }` (was just `"Insignia"`)
- Death Knight removed from class filter (Ascension doesn't ship the DK class)
- Mousewheel scrollbar thumb fix in the Browser
- Channel optimizations: skip PARTY/RAID broadcast when group is fully guildies, sync responses go via WHISPER instead of GUILD-broadcasting
- 4x faster sync (`BROADCAST_STAGGER` 2.0s → 0.5s)
- Realistic sync ETA based on peer DB size
- Self DB count shows in Scanners view leaderboard
- Version notification only fires on major.minor bumps (1.1.x → 1.1.y stays silent; 1.1 → 1.2 notifies)

### Wire format summary

Position 40 is now defined and used for item-info hints. Backward-compatible — pre-v1.2 receivers just ignore the field.

### Stable surface

- Wire protocol positions 1–30 still frozen
- Position 40 now defined (additive, optional)
- SavedVariables shape unchanged (`EpogArmoryDB`, `EpogItemCacheDB`)
- `_G.EpogArmory.*` API: `MyIdentity`, `HasRealityAura`, `RealityAuraName`, plus existing sync/peer accessors

---

## EpogArmory v1.1.5 — Broaden weapon slot acceptance *(2026-04-28)*

User ran v1.1.4 cachebuild on a real DB: 3216 of 3221 items cached cleanly (vs near-zero before the spam fix). Only 3 items kept failing verification:

- `Barman Shanker` (vanilla itemID 12791) — INVTYPE_WEAPONMAINHAND in slot 17
- `Mam'toth's Fist` (Ascension custom itemID 60454) — INVTYPE_WEAPONMAINHAND in slot 17
- `Merc Sword` (vanilla itemID 4567) — INVTYPE_2HWEAPON in slot 17

These aren't itemID reassignments — `CMSG_ITEM_QUERY_SINGLE` returns the same equipLoc the client DBC has. Ascension's classless server simply allows MAINHAND-labeled and 2H weapons in slot 17 even without Titan's Grip. The items render correctly (right name, right stats); they're just classified as "wrong sub-type" for the slot they sit in.

The verification was designed to catch **wrong-category** mismatches (boots in a cloak slot — categorically impossible). For weapon-vs-weapon sub-type differences in a weapon slot, the items display fine; the verification was just generating noise.

Fix: slot 16 and slot 17 now accept ALL weapon equipLocs (`INVTYPE_WEAPON`, `INVTYPE_2HWEAPON`, `INVTYPE_WEAPONMAINHAND`, `INVTYPE_WEAPONOFFHAND`). Slot 17 still also accepts `INVTYPE_SHIELD` and `INVTYPE_HOLDABLE` for off-hand non-weapon options. The strict cross-category check (boots vs cloak vs weapon) still fires correctly — only sub-type drift is now ignored.

### Pending-cache backoff re-trigger

Also added a single re-fire of `SetHyperlink` for pending items that haven't received a server response within 10 seconds. The initial fetch goes out on `MarkPendingCache`; if 10s passes with no `GetItemInfo` data arriving, fire once more. Gives the server a second chance without re-introducing the per-tick spam from v1.1.3. Helps for items where the first query was dropped under flood conditions.

---

## EpogArmory v1.1.4 — Stop fetch-spam, pass full link, bump timeout *(2026-04-28)*

User ran v1.1.3's `/epogarmory cachebuild` on a real DB (3221 items, 1188 needing fetch). Result: the dump showed almost everything still `Cache: (not cached)` after a full minute. Diagnosed three problems with the fetch path; fixed all.

### Bug 1: TriggerItemFetch fired on every retry tick

```
TryCachePending tick (every 0.25s) → CacheItemInfo → GetItemInfo nil → TriggerItemFetch
```

For 1188 pending items, that's ~4750 `SetHyperlink` calls per second. The client and server can't sustain that — queries get dropped, server stops responding. **Fix:** removed the `TriggerItemFetch` call from `CacheItemInfo`'s nil branch. The fetch is already triggered once when `MarkPendingCache` adds the item; subsequent retries just poll `GetItemInfo` until the response lands.

### Bug 2: Slot-mismatch verify also re-fired on every tick

Same pattern in the verification branch — every retry called `TriggerItemFetch` again. **Fix:** added a 2-second time gate via `lastVerifyAt`. Per-item retries now happen at most every 2 seconds (still fits within 3 attempts × 2s = 6s, well under `CACHE_GIVE_UP`).

### Bug 3: Bare `item:itemID` query instead of full link

`TriggerItemFetch` was calling `SetHyperlink("item:" .. itemID)` — the bare itemID format. Ascension's server-side custom items have suffix/enchant/gem data that may matter for the lookup. **Fix:** `TriggerItemFetch` now accepts the full itemstring (passed from `MarkPendingCache` and the slot-mismatch retry path), so the query carries the original payload.

### Tuning: CACHE_GIVE_UP 15s → 60s

Mass cachebuild on Ascension custom-itemID payloads needs time. With the spam fixed, the natural pace is much slower — bumped the give-up timeout to 60s so we don't drop pending entries before the server has a chance to respond.

### Slot map kept strict

Initial draft of v1.1.4 broadened slot 17 to accept INVTYPE_2HWEAPON / INVTYPE_WEAPONMAINHAND, hypothesizing Titan's Grip-style configurations on the classless system. **User confirmed Titan's Grip is not a thing on Ascension** — so those mismatches ARE genuine reassignments to fix via server query, not false positives to mask. Reverted to the original strict slot map.

### What to do after upgrading

1. `/reload` or relog.
2. Run `/epogarmory cachebuild` — should now actually populate over the next ~30 seconds without flooding.
3. `/epogarmory dump <player>` — verified items should annotate as `✓verified`; reassigned itemIDs should heal as the server's real data arrives.

---

## EpogArmory v1.1.3 — Slot-based item verification (heals reassigned itemIDs) *(2026-04-28)*

The `/epogarmory dump` output revealed Ascension reassigns vanilla itemIDs server-side. Example from a real scan:

```
slot 15 (back):     itemID 13340 → "Chainmail Boots"   Armor/Mail @ INVTYPE_FEET
slot 16 (mainhand): itemID 90102 → "Loose Chain Pants" Armor/Mail @ INVTYPE_LEGS
```

Boots in the back slot, pants in mainhand — impossible under valid data. Cause: the server's database has reassigned those itemIDs to custom raid items, but the client's local DBC files still contain the original vanilla data. `GetItemInfo` reads DBC and returns the stale info. Live tooltips work correctly because `SetHyperlink` triggers `CMSG_ITEM_QUERY_SINGLE` → server responds with `SMSG_QUERY_ITEM_RESPONSE` → updates the client's *dynamic* cache, which overrides DBC. Our addon's cache fill never triggered the server query because `GetItemInfo` returned non-nil (just wrong) data, so we confidently cached the vanilla item info.

### Fix: detect mismatch + re-fetch + cache verified state

Per user feedback, "can we figure out if that item actually needs a query first, and cache the result so we don't query repeatedly?" — yes. Added per-cache-entry verification:

```lua
local EXPECTED_INVTYPE_BY_SLOT = {
    [15] = { ["INVTYPE_CLOAK"] = true },
    [16] = { ["INVTYPE_WEAPON"] = true, ["INVTYPE_2HWEAPON"] = true, ["INVTYPE_WEAPONMAINHAND"] = true },
    -- ... all 19 slots mapped to valid INVTYPE strings
}
```

When `CacheItemInfo` is called with slot context (now passed everywhere it's reachable from gear iteration):

1. **Check existing cache.** If entry is verified (`equipLoc` matched the slot last time), short-circuit and return.
2. **Call `GetItemInfo`.** Get the equipLoc.
3. **Verify.** If `equipLoc` fits the slot — cache as verified, done.
4. **Mismatch path:**
   - Force `SetHyperlink` to refresh the dynamic cache from server.
   - Increment `verifyAttempts`. Cap at 3.
   - Don't write the (stale) data — keep the prior entry, queue for retry via `pendingCache`.
   - Pending-cache flow re-runs `CacheItemInfo` after a short delay. By then, the dynamic cache has the server's real data and the next `GetItemInfo` returns the correct equipLoc.
5. **Give up after 3 attempts** (server doesn't have updated data for this ID either) — cache what we have but mark `verified = false`.

### New cache fields (CACHE_SCHEMA v10 → v11)

- `equipLoc` — the slot type GetItemInfo returned (for verification + dump diagnostics)
- `verified` — `true` if equipLoc matched observed slot, `false` if we gave up after retries
- `verifyAttempts` — retry count, persisted so we don't loop across sessions
- `lastVerifyAt` — unix ts of last verification attempt

Existing v10 entries lack these fields and are now treated as "needs verification" — they get re-validated on next observation. Entries that are correct stay correct (verification passes, marked verified, never re-queried).

### Healing existing wrong cache

Running `/epogarmory cachebuild` walks every stored player's gear and calls `CacheItemInfo` with slot context for each itemID. With v1.1.3, that now triggers verification across the whole DB in one pass.

### Dump command shows verification status

The `/epogarmory dump` output now annotates each cache entry with `✓verified` (green) or `✗unverified (attempts=N, equipLoc=X)` (red).

### Cost analysis

- Verified items: zero overhead (early-out at the cache lookup).
- Unverified items: one `SetHyperlink` per attempt, capped at 3. Persisted, so a future session doesn't re-attempt unless cache schema bumps again.
- Schema bump healing: items not currently observable (player not stored anymore) stay at v10 stale and are never re-touched. No background mass-query.

---

## EpogArmory v1.1.2 — Dump command: PvP detection trace *(2026-04-28)*

User clarified their problem trinket actually contained "Insignia" — so v1.1.1's "Medallion broadening" hypothesis didn't apply to their case. Something else caused the routing to miss.

Extended `/epogarmory dump` with a per-set **PvP detection trace** that exposes the actual routing decision for each stored set. For each trinket slot:

```
PvP detection trace (live, using current patterns):
  slot 13 (trinket1): "Insignia of the Alliance" — matches pattern "Insignia" → PvP
  slot 14 (trinket2): (empty)
  live verdict: would route to sets["pvp"]
  ⚠ MISMATCH: stored as set 1 but live detection says PvP. Likely cause:
    scan was made before v0.33 (PvP routing didn't exist), OR GetItemInfo
    returned nil for the trinket at scan time. Fix: rescan with the
    trinket equipped.
```

The trace shows whether the trinket name is currently resolvable, whether any pattern matches, and warns when stored routing disagrees with live evaluation. That diagnoses three cases:

1. **Pre-v0.33 stale scan** — live says PvP, stored says non-PvP, but the trinket name resolves now → "rescan to fix."
2. **Cache miss at scan time** — live says PvP, stored says non-PvP, name resolves now (was nil then) → also "rescan to fix."
3. **Pattern coverage gap** — live says non-PvP but the user knows it's a PvP trinket → tells us we need to add a new pattern.

Run `/epogarmory dump <playername>` on the affected entry and the output will tell us which case it is.

---

## EpogArmory v1.1.1 — Dump diagnostic + broader PvP trinket detection *(2026-04-28)*

Two patches: a forensic dump command for the transmog investigation, and a fix for the "Insignia/Medallion equipped but routed to non-PvP set" bug.

### Versioning policy

This and future small fixes go to `v1.1.X`. `v1.2` reserved for actual minor releases (new feature surfaces).

### Patch 1: `/epogarmory dump <playerName>`

Forensic diagnostic for investigating gear-display anomalies (transmog or otherwise). For each set (set 1/2/3/pvp) of the stored player, prints all 19 slots with:

1. **Raw itemstring** + **field count** — standard 3.3.5 itemstring is `itemID:enchant:gem1:gem2:gem3:gem4:suffix:unique:level` (9 fields). Anything more = Ascension server-side extension (custom stats / reforge / transmog). Extras dumped explicitly.
2. **`GetItemInfo(itemID)`** — name, quality, ilvl, type, subtype, equipLoc.
3. **`GetItemInfo(fullLink)`** — same lookup with the full itemstring. If the result differs from the itemID-only lookup, the link's extra fields are altering resolution — that's a smoking gun.
4. **`GetItemStats(fullLink)`** — every stat key/value pair. Compare to live tooltip stats.
5. **`EpogItemCacheDB[itemID]`** — what we have cached (name, quality, ilvl, icon, schema version).

Output is verbose but designed for chat scrollback (~5-7 lines per occupied slot). Run on a known-affected player and we can pinpoint where the divergence happens.

### Patch 2: PvP trinket detection now catches Medallion + Battlemaster's

User noted an Insignia trinket ended up stored under their assassination set instead of the `pvp` set. Looking at the detection rules, two failure modes:

- **Pattern was too narrow.** `PVP_TRINKET_NAME_PATTERNS = { "Insignia" }` missed `"Medallion of the Alliance/Horde"` entirely — a Medallion-equipped scan would route to the dominant-tree set instead of `sets["pvp"]`. Broadened to `{ "Insignia", "Medallion", "Battlemaster's" }`.
- **Stale stored sets won't auto-rewrite.** PvP routing landed in v0.33; any set scanned before that (or with a Medallion that the old pattern missed) is stuck wherever it was originally stored. The detection rules only apply at scan time. To fix existing stale sets: just rescan — equip the PvP trinket and the next self-scan will route correctly. Old set 1 entry stays until something overwrites it (or you wipe).

This is purely a detection broadening. The wire protocol and routing logic are unchanged.

### No protocol changes

Both patches are local. No new wire messages, no SavedVariables shape change, no compat concerns.

---

---

## EpogArmory v1.1 — Pause auto-scan while manual inspect is open *(2026-04-26)*

User reported that when they manually inspect someone via the Blizzard inspect frame and the addon's auto-scanner fires concurrently, the items in their inspect window become un-hoverable.

Cause: WoW 3.3.5 has a single global "inspect target" slot. Calling `NotifyInspect` retargets it. When the addon called `NotifyInspect("partyN")` while the user had a manual inspect open, it overwrote the manual inspect's target — making all the cached item links in the user's frame point to a different unit (or be invalidated entirely).

### Fix

Two defensive guards:

1. **`TryInspect` early-return:** if `InspectFrame` is shown, hold the queue without dropping items and re-check in 1s. The user's frame stays untouched. As soon as they close it, the scanner resumes from where it left off.

2. **`OnInspectReady` drop-and-retry:** if the inspect-ready event fires while the manual frame is open (race: user opened it between our `NotifyInspect` and the response), discard the data and re-queue our target for `OUT_OF_RANGE_COOLDOWN`. Avoids saving potentially-wrong data attributed to our target's GUID.

### `InspectFrame` lazy-load handled

`InspectFrame` is created by `Blizzard_InspectUI` (LoadOnDemand). The `InspectFrame and InspectFrame:IsShown()` guard short-circuits cleanly when the user has never opened the inspect UI in this session.

---

## EpogArmory v1.0 — First stable release *(2026-04-26)*

After ~50 prereleases of iteration, EpogArmory graduates from `v0.x` prerelease to the first stable `v1.0`. No new features in this cut — it's the v0.54 codebase with a version bump and a recap of what the addon does.

### What it is

A WoW 3.3.5 / Project Ascension addon that lets you open an in-game paperdoll for **any player on the server** that's been seen by anyone in the mesh — no group required, no interact range required, no line of sight required.

### Core features

- **Mesh-based gear inspector.** Every running client auto-inspects groupmates in dungeons/raids and broadcasts the gear, talents, and spec icon over addon-message channels. Receivers store the data locally; from then on, anyone in the mesh can pull up that player's paperdoll via the browser.
- **Per-spec gear sets.** Up to 3 stored sets per player keyed by dominant talent tree, plus a `pvp` set automatically routed when an Insignia trinket is equipped (covers Ascension's classless dual-spec patterns).
- **Item cache (`EpogItemCacheDB`).** Every observed itemID gets `GetItemInfo` + `GetItemStats` cached, so Ascension's modified stats and server-custom items survive the upload to the public armory site.

### Discoverability + sync

- **Browser** (`/epogarmory` or minimap shield) with two views:
  - **Players view** — searchable + class-filterable table of every stored player. Class-colored name, class, last-scan age. Click → paperdoll.
  - **Scanners view** — leaderboard of who's contributed what, with `Contrib`, `In DB`, `Last seen` columns. Click → request a sync from that peer.
- **`syncfrom` admin command** to bulk-pull stored sets from a specific peer. v0.46 manifest dedup means only sets you don't already have are sent. v0.51 4x faster pacing means a 100-entry sync finishes in ~3 minutes (down from ~13).
- **Refresh Peers button** to actively poll the guild for fresh identity + DB-size info instead of waiting for organic broadcasts.

### Identity + alts

- **Main-name consolidation.** Multiple alts of the same user roll up under one canonical identity in the Scanners leaderboard. `/epogarmory main <character>` picks the canonical name; retro consolidation rewrites past attributions on rename.
- **`/epogarmory merge`** to admin-correct cross-peer alias splits.

### Hygiene

- **Self-scan filtering** drops mount-speed enchants, Mithril Spurs boots, Riding Crop trinkets, Chef's Hat, fishing poles, and PvP loadouts from the wrong context. Bank-alt scans don't pollute the mesh.
- **24h mesh cooldown** per player GUID prevents redundant re-scanning across the network.
- **30-day auto-prune** of inactive scanners keeps the leaderboard focused on currently-active peers.
- **Sender-side level gate** — L<60 alts don't broadcast (they'd just clutter receivers' DBs).

### Network behavior

- **Manifest-based sync** (v0.46) — requester sends a compact `(guid:group:scanTime;...)` manifest; responder skips anything you already have at ≥ their scanTime. Eliminates the dominant duplicate-send waste on full-DB pulls.
- **Channel optimizations** (v0.53):
  - Skips PARTY/RAID broadcast when every group member is also in your guild — the GUILD broadcast already reaches them.
  - Sync responses go via WHISPER to the requester's character instead of GUILD-broadcasting (saves the "every guildmate ingests 200 sync replays as collateral" cost).
- **Tightened pacing** (v0.51) — `BROADCAST_STAGGER` 2.0s → 0.5s = 4x faster syncs while still under the 800 B/s addon-channel safe budget.
- **Backward-compatible** wire format — additive fields at the tail (positions 31+) so older clients keep working.

### What's stable

- Wire protocol (positions 1–30 frozen since v0.13)
- SavedVariables shape (`EpogArmoryDB`, `EpogItemCacheDB`)
- Slash command surface
- All public `_G.EpogArmory.*` API exposed for the UI

Future v1.x releases will be feature additions and bug fixes; the protocol and storage layout are committed.

---

## EpogArmory v0.54 — Fix scrollbar thumb not moving on mousewheel *(2026-04-26)*

User: "When scrolling in the Players frame the scrolling works but the actual visual scrolling bar is just static. Doesn't move downwards."

Cause: the v0.38 mousewheel handler called `FauxScrollFrame_SetOffset` directly, which updates the internal offset (so the list moves) but never tells the scrollbar widget about the new position (so the thumb stays frozen). The keyboard/click scrollbar path goes through `OnVerticalScroll` → `FauxScrollFrame_OnVerticalScroll` which updates both — the mousewheel was bypassing it.

Fix: route mousewheel through the scrollbar's `SetValue` instead. That triggers `OnValueChanged` → `OnVerticalScroll` → the existing handler, which updates offset + thumb in one go. Single source of truth for scroll state regardless of input method.

Step size kept at 3 rows per wheel tick (now expressed in pixels: `3 * BROWSER_ROW_HEIGHT`).

Fallback path preserved: if the scrollbar widget reference somehow isn't available, falls back to the old offset-only behavior so the wheel still works.

---

## EpogArmory v0.53 — Channel noise reduction (skip dual-broadcast + whisper sync responses) *(2026-04-26)*

Two targeted bandwidth optimizations after discussion of mesh-protocol redesigns. The "in-game custom channel + pull-based protocol" idea was ruled out because (a) WoW 3.3.5's `SendAddonMessage` doesn't support custom channels (added in Cataclysm), and (b) the math didn't favor pull-based on a guild-scale mesh. These two are the realistic wins.

### 1. Skip PARTY/RAID broadcast when the whole group is guildies

Previously every gear scan went to BOTH `PARTY/RAID` AND `GUILD` (per `PickChannels`). For a 5-man dungeon of guildmates, every party member received the broadcast twice — once via PARTY, once via GUILD.

New `AllGroupAreGuildies()` helper builds a guild-roster set, then checks each party/raid member against it. If everyone matches, `PickChannels` returns just `{GUILD}` instead of `{PARTY, GUILD}`. Halves traffic for all-guild dungeons/raids.

Failsafe: if guild roster isn't populated yet (e.g. early after login, before the first `GUILD_ROSTER_UPDATE`), the helper returns false and we send on both channels — current behavior. No data loss, just no optimization until the roster fills.

### 2. Whisper sync responses instead of GUILD-broadcasting

`HandleSyncRequest` previously replayed up to 200 sets to the GUILD channel — meaning every guildmate ingested all of them as a side-effect (free benefit, but expensive for them). On a sync of a 200-entry DB across a 50-person guild, that was 200 sets × 50 listeners = 10,000 ingest operations to deliver to one requester.

Now uses WHISPER addressed to `sender` (the actual character that sent the SYNCREQ — works whether or not they have `mainName` set). Only the requester pays ingest cost. The "everyone catches up for free" side benefit is gone — explicit trade-off accepted.

`outQueue` items now optionally carry a `target` field; the OnUpdate send loop passes it as the 4th arg to `SendAddonMessage`. Other channel types ignore the 4th arg, so non-whisper sends are unaffected.

### Why these two and not the bigger redesign

The bigger "notify-then-pull" redesign would have cost more than it saved on a guild-scale mesh — broadcast is essentially free per additional receiver, while pull-based pays per receiver. These two changes capture the wins (less duplicate delivery, less guild-wide collateral ingest) without protocol-level complexity.

---

## EpogArmory v0.52 — Show your own DB count in the Scanners view *(2026-04-26)*

User noted their own row in the Scanners view always showed `—` in the In DB column. Cause: `Ingest`'s `effectiveScanner ~= MyIdentity()` guard explicitly skips writing self to peerInfo (peerInfo is meant for tracking other peers). The Scanners view's `In DB` column reads from peerInfo, so self → no entry → `—`.

Fix: `AggregateScanners` now injects self's `reportedDB` inline by counting `EpogArmoryDB.players` directly. Only sets `reportedDB`, leaves `reportedAt` alone — the Last column keeps using `lastContribution` (when you last self-scanned), which is the meaningful "last activity" signal for self.

Implementation: exposed `_G.EpogArmory.MyIdentity` so the UI can detect "is this leaderboard row me" without duplicating the main-name resolution logic.

Edge case: if you've never self-scanned and have no contributions, you don't appear in the leaderboard at all (correct — you're not contributing to the network from anyone's perspective). Once your first self-scan lands, you show up with a real DB count.

---

## EpogArmory v0.51 — 4x faster sync (BROADCAST_STAGGER 2.0s → 0.5s) *(2026-04-26)*

User asked if syncs really need to be that slow. The honest answer was no — `BROADCAST_STAGGER = 2.0` was set in v0.13 when the only outbound traffic was rare organic inspect broadcasts (no urgency). When `syncfrom` arrived in v0.35 it inherited the same pacing, even though now the user is actively waiting on a 200-set bulk transfer.

### The numbers

```
WoW 3.3.5 addon-channel safe budget: ~800 B/s  (ChatThrottleLib default)
Old:  225 B/msg / 2.0s stagger = 112 B/s  (14% of budget — over-cautious)
New:  225 B/msg / 0.5s stagger = 450 B/s  (56% of budget — still leaves
                                           room for DBM/Recount/etc)
```

### Effect

| Peer DB size | Old ETA | New ETA |
|---|---|---|
| 45 entries | ~6 min | ~1.5 min |
| 100 entries | ~13 min | ~3.5 min |
| 200 entries (cap) | ~27 min | ~7 min |

ETA math in `/epogarmory syncfrom` recomputed for the new pacing: ~2s/set instead of ~8s/set. `SYNC_EST_DURATION` (the fallback when peerInfo is missing) tightened from `25*60` → `8*60` for the same reason.

### Why this is safe

Every outgoing addon message is ~225 bytes (200B body + ~25B chunk header). At 450 B/s sustained we sit at ~56% of the 800 B/s budget that DBM/Recount/Details share with us. During raid pulls when their traffic spikes, we're still well under the disconnect threshold. Per-peer outgoing rate is what matters — concurrent syncs to different peers don't aggregate from the receiver's POV.

The 200-set cap on responder side stays — that's a safety bound, not a speed knob.

### Side benefit

All other broadcasts (self-scans, version pings, peer pings) also drain 4x faster — gear updates show up in the mesh in ~1s instead of ~4s when there's a small queue.

---

## EpogArmory v0.50 — Realistic sync ETA based on peer DB size *(2026-04-26)*

User noted the sync request always claims `ETA ~25 min` regardless of how much data the peer actually has. That's the worst-case ceiling (200-set cap × ~8s/set), not the actual time. For a peer with 45 entries, the real ceiling is ~6 min; with v0.46 manifest dedup it's typically much less.

### What changed

`/epogarmory syncfrom` now reads `peerInfo[name].dbSize` (when known — present for any peer running v0.36+) and computes a realistic upper bound:

```
estimatedSets = min(reportedDB, SYNC_MAX_SETS_PER_RESPONSE=200)
etaSeconds    = estimatedSets * 8 + 60   -- 8s/set + 60s safety
```

Message now reads:
```
EpogArmory: requested sync from Xtarsia (last 7 days) via GUILD. ETA ~7 min (peer has ~45 entries).
```

### Side benefit: faster row un-greying

`activeSyncs[name]` (the timestamp that greys out the row in the Scanners view and rate-limits a duplicate sync request) now uses the same realistic ETA. Previously, after a 3-minute sync from a small-DB peer, the row would stay greyed for another 22 minutes for no reason. Now it un-greys when the actual sync should be done.

### Fallback

If we have no `peerInfo` entry for the target (peer never broadcast / pre-v0.36 client / pruned by 30-day staleness sweep), the estimate falls back to the old 25-minute upper bound — same as before.

The "concurrent sync limit" message no longer quotes a fixed "~25 min" either (also varies now); just says to check the Scanners-view countdowns.

---

## EpogArmory v0.49 — Scanners view: columnar table *(2026-04-26)*

User request: structure the Scanners view as columns too — Rank, Name, Contributions, In DB, Last seen. Confirmed by user that Contributions and In DB are separate stats:

- **Contributions** = sets stored in YOUR DB that this scanner originally captured (pulled from `set.scannedBy` on each stored set). "How much they've added to your pool."
- **In DB** = total entries that scanner has in THEIR own DB at last broadcast (carried on wire position 38 of every gear scan). "How much they have to share with you."

Both shown side-by-side now instead of the previous mutually-exclusive `N contributed` / `N in DB` line.

### Column layout

Five columns per row, ~266px row width on the 320px frame:

| Col | Width | Align | Content |
|---|---|---|---|
| `#` | 24px | left | Leaderboard rank `#1`–`#99` |
| Name | 94px | left | Peer name (white if reachable, gray if not) |
| Contrib | 40px | right | Sets they originally captured that you hold |
| In DB | 36px | right | Their total DB size (yellow), or `—` if unknown |
| Last | 50px | right | Most recent signal age (`5m ago`, `2h ago`, `3d ago`) |

Gold header row in the gap above the scroll: `#  Name  Contrib  In DB  Last`.

### Active-sync state

When a sync from this peer is in flight, the **In DB** column shows `sync` (cyan) and the **Last** column shows `~5m` (countdown). Other columns continue to show their normal data so you can still see name + contributions while the sync runs.

### Unknown / missing data

- If we've never received a broadcast from them: **In DB** = `—`
- If we have no last-seen signal at all: **Last** = `—`

### Mode toggle

Clean separation: Players mode shows player columns + headers; Scanners mode shows scanner columns + headers. The two sets of FontStrings are parented to the same row so `row:Hide()` (for empty rows beyond the list) cascades to all of them — no leakage.

---

## EpogArmory v0.48.1 — Drop Death Knight from class filter *(2026-04-26)*

User noted that Death Knight isn't a class on Ascension — the server doesn't ship the DK starting experience, so no player has classFile = "DEATHKNIGHT". Removed it from the class filter dropdown. Nine vanilla classes remain.

---

## EpogArmory v0.48 — Players view: columnar table + class filter *(2026-04-26)*

User request: "On the frame for players where we can choose who to inspect, can we make the table with columns so it's structured? For example Classes in one column and Last scan in right column. Also we need to be able to filter on classes here. Level is not needed because it's only for level 60s."

### Columnar layout

Each Players-view row was previously a single concatenated string (`<colored name>  L60 <class>  <age>`). Replaced with three explicit columns:

- **Name** (~110px, left-aligned) — class-colored player name
- **Class** (~75px, left-aligned) — class name, also class-colored
- **Last Scan** (~70px, right-aligned) — age-tinted (green = <1h, yellow = <24h, gray = stale)

A header row sits in the gap above the scroll frame: `Name  Class  Last Scan` in gold. No scroll height lost — the header lives in dead space that already existed between the search row and the scroll top.

The Level field is dropped — `MIN_STORE_LEVEL = 60` already gates everything stored, so it was always "L60". Removing it freed horizontal space.

### Class filter

A new `Class: All ▼` button sits to the right of the search box. Click → UIDropDownMenu pops with `All Classes` + the 10 WotLK classes (Death Knight, Druid, Hunter, Mage, Paladin, Priest, Rogue, Shaman, Warlock, Warrior). Each entry colored with its class color for quick scanning.

Filter state stored on the frame as `f.classFilter` (uppercase classFile string, or nil for All). UpdatePlayersMode applies it as `p.class == classFilter` — instant, no allocation. Compatible with the search-box name filter — both apply together.

The footer count line includes the active class filter when set: `12 of 247 match (Druid)` instead of the bare `12 of 247 match`.

### Search box

Shrunk from 180px to 100px to make room for the class filter on the same row. Long names still fit (the box scrolls horizontally on text overflow — Blizzard InputBox default).

### Scanners view

Untouched — still uses the single-line `row.text` rendering with rank, peer name, DB size, age. The columnar layout is Players-only. Toggling between modes shows/hides the right widgets cleanly: column headers + filter button visible only in Players mode; accept-sync checkbox + Refresh Peers button visible only in Scanners mode.

### Implementation note

Added three column FontStrings per row (`row.colName`, `row.colClass`, `row.colAge`) parented to the row frame. Players mode shows them and hides `row.text`; Scanners mode shows `row.text` and hides the columns. `row:Hide()` (for empty rows beyond the list end) cascades to all children — no leakage.

---

## EpogArmory v0.47.1 — Footer layout fix *(2026-04-26)*

User reported the new Refresh Peers button overlapped the "Accept sync requests from others" checkbox label. Both controls live on the same footer row of a 320px-wide frame, and the long label ran past where the button's left edge sat.

Fix: shortened the checkbox label to "Accept sync requests" (drops the redundant "from others" — same intent, ~70px shorter) and narrowed the button slightly. Both now fit cleanly side-by-side: checkbox + label on the left, button on the right.

---

## EpogArmory v0.47 — "Refresh Peers" button + lightweight peer ping *(2026-04-26)*

User request: "Can we add a command similar to syncfrom where we basically just ask everyone in guild 'Give me your latest updates' that will update the list of scanners if I am missing any, and how many entries they have in their DB. This should be a button in the bottom right of the Scanners frame."

### What it does

- New **Refresh Peers** button bottom-right of the Scanners view. One click broadcasts a tiny `PEERPING` to your guild + group; every guildmate running v0.47+ replies with their current identity, DB size, version, and character name.
- Each response refreshes the responder's `peerInfo` entry, so the Scanners leaderboard updates with newly-discovered peers and current entry counts without having to wait for an organic gear-scan broadcast.

### Why the existing flow wasn't enough

`peerInfo` was previously updated only as a side-effect of full gear-scan broadcasts (positions 38/39 carry dbSize + senderMain). If a peer hadn't done a scan recently, you'd have stale or missing info on them. The Refresh Peers button polls actively — useful before deciding who to `syncfrom`.

### Wire format

```
PEERPING^<requester>                                  -- broadcast
PEERPONG^<identity>^<dbSize>^<version>^<charName>     -- reply
```

Replies go on the same channel the request arrived on (GUILD/PARTY/RAID).

### Rate limiting

- **User-side**: button can be pressed at most once every 60s. Visual disable for 5s after a press.
- **Responder-side**: per-requester 60s cooldown so a misbehaving client can't loop-spam.
- Channel choice: same `PickChannels()` as everything else (RAID > PARTY, plus GUILD if in one).

### Slash command

`/epogarmory refreshpeers` (or `/epogarmory refresh`) — same effect as the button, listed in `/epogarmory` help.

### Backward compatibility

Old clients (≤v0.46) that receive a `PEERPING` see an unknown-tag payload, fall through past the VER/SYNCREQ/PEERPING/PEERPONG branches in `OnAddonMessage`, end up in `Ingest` which fails to parse it as a gear payload and silently drops it. No errors, no responses — they just don't participate in the refresh until they update.

---

## EpogArmory v0.46 — Manifest-based sync (kill duplicate-send waste) *(2026-04-22)*

User report from a guild sync: "I now get a lot of `[store] SKIP: Poonchy (set 3) — existing set is newer (20:02:32 vs 20:02:32)`" — the responder was sending sets the requester already had at the same scanTime, the requester ingested them, validated them, and rejected as not-newer. Pure bandwidth waste, and on a 100+ player DB that's most of the response.

### Manifest exchange in SYNCREQ

The requester now packs a compact manifest of "what I already have" into the SYNCREQ payload. Format:

```
SYNCREQ^<requester>^<target>^<sinceTS>^<manifest>
manifest = "guid1:group1:scanTime1;guid2:group2:scanTime2;..."
```

Per-(guid, group) entries — not per-player max scanTime — because a player can have spec-1 from yesterday and spec-2 from a month ago, and we need to ask for spec-2 without re-getting spec-1.

The responder calls `ParseSyncManifest` to build a `requesterHas[guid][group] = scanTime` lookup, then in the iteration skips any `(guid, set)` where `requesterHas[guid][tostring(setKey)] >= set.scanTime`. The new debug line: `[sync] responding to <name>: queued N, skipped M (already fresh) since <ts>`.

### Sizing + chunking

Each manifest entry is ~30 bytes. A 100-player DB with ~1.5 sets average is ~150 entries ≈ 4.5 KB. That exceeds a single addon-message chunk, so the outgoing SYNCREQ now goes through `MakeChunks` (was hard-coded as `^1^1^`). Reassembly on the responder uses the existing pipeline — no protocol change there.

### Backward compatibility

- **Old responder (≤v0.45) receives v0.46 SYNCREQ:** sees an extra `^<manifest>` field, `strsplit` returns it as the 5th value which the old code ignores. Manifest absent on the responder side → sends everything as before. No regression.
- **v0.46 responder receives old (≤v0.45) SYNCREQ:** `manifestStr` is nil, `ParseSyncManifest("")` returns `{}`, dedup check `requesterHas[guid] and ...` always falls through → sends everything as before. No regression.
- **Both sides on v0.46:** dedup kicks in, expect "skipped M" to dominate "queued N" once a sync has been done once.

The optimization is opportunistic — both peers must be on v0.46 for the win, but neither side breaks if mixed.

---

## EpogArmory v0.45 — Auto-default main + scroll-offset fix + 30-day prune *(2026-04-26)*

Three follow-ups from user feedback on v0.44.

### 1. Bug fix — empty Scanners list with non-zero count

User report: "Scanners footer says '6 scanners (1 online)' but the list shows zero rows." Cause: when toggling between Players and Scanners modes, the `FauxScrollFrame` scroll offset wasn't reset. If you had scrolled down to row 50 in Players (100 entries), the offset stayed at 50. Switching to Scanners (6 entries), every visible row tried to render `list[51..74]` — all nil — so all rows hid. The footer used `#list = 6` and rendered correctly.

Fix: `FauxScrollFrame_SetOffset(scroll, 0)` + `scroll.ScrollBar:SetValue(0)` on every mode toggle. Now switching views always starts at the top of the new list.

### 2. Auto-default mainName to first L60 character

Most users want the alt-consolidation feature; making them discover and run `/epogarmory main` is friction. v0.45: on `PLAYER_LOGIN`, if `EpogArmoryDB.config.mainName` is nil AND the current character is L60+, auto-set it to the current character. Account-wide via SavedVariables, so it sticks — subsequent logins on different characters don't change the auto-set value.

User-visible:
```
EpogArmory: auto-set main identity to Defcon (first L60 to log in). Change with /epogarmory main.
```

Logging in on an alt below L60 (e.g. Defcoil L33) does NOT auto-set — the gate waits for the first L60 to log in. Once set (manually or auto), the value sticks.

### 3. Auto-prune scanners inactive 30+ days

Two paths combine to keep the Scanners view focused on currently-active peers:

- **`PLAYER_LOGIN` cleanup** — walks `EpogArmoryDB.peerInfo`, removes entries with `lastSeen < (time() - 30 * 86400)`. Frees storage; debug logs `[migrate] pruned N stale peerInfo entries (>30d)`.
- **`AggregateScanners` display filter** — also drops contributor-only entries (in `set.scannedBy` but with no fresh peerInfo) when their latest contribution is also >30 days old. Catches scanners that never broadcast their DB size but contributed once long ago.

Net effect: scanners that haven't been active in the last 30 days disappear from the leaderboard. Their attribution on individual stored sets stays intact (we don't rewrite `scannedBy` — just stop showing them as their own row).

---

## EpogArmory v0.44 — Main-name UX + local merge + retro consolidation *(2026-04-26)*

User testing on v0.43 surfaced three issues with the alt-consolidation flow. All addressed in v0.44.

### 1. `/epogarmory main` display ambiguity

The "no main set" output was `"main identity = Defcoil (defaulting to current character)"` — easy to misread as "the main IS Defcoil and changes per character". Now reads `"NOT SET — broadcasts will attribute to whichever character is currently logged in (now: Defcoil)"`. The configured case explicitly notes "(account-wide, persists across all your characters)" so users understand the scope.

### 2. Retro consolidation when setting/changing main

Setting `mainName` previously only affected *future* broadcasts. Past scans you'd captured under your various character names stayed under those names — your contributions appeared as 3-4 separate scanners in the leaderboard even after you set a main. v0.44: when you set or change your main, all `set.scannedBy` entries matching either the previous mainName OR any of your known character names get rewritten to the new main. `peerInfo` entries get merged the same way (largest dbSize wins; latest lastSeen wins; lastCharName preserved).

Output line now also reports the consolidation:
```
EpogArmory: main identity = Defcon (account-wide; ...)
  Consolidated: 87 stored scans + 3 peer entries from your alts → Defcon
```

Cross-mesh consolidation (other guildies' DBs) still requires either:
- Their next ingest of one of your future broadcasts (which carry your main name) — gradual catch-up
- Them running the new merge command (below) on your aliases

### 3. New `/epogarmory merge` admin command

```
/epogarmory merge <newname> <alias1> [alias2] [alias3] ...
```

Locally rewrites `scannedBy` and `peerInfo` from the listed aliases into `<newname>`. Useful when you can see "Yippie" / "Yippee" / "Yiippee" in the Scanners view, know they're the same player, but they haven't set their main yet.

Example use:
```
/epogarmory merge Yippie Yiippee Yippee
EpogArmory: merged 31 scan attributions + 2 peer entries → Yippie
  Local-only — other guildies still see the original names until they merge too.
```

Same merge logic as the main-rename consolidation. **Local only** — purely a per-client view fix; other guildies' DBs still show the original names until they run merge themselves (or the alt owner sets their main + new broadcasts propagate naturally).

### Account-wide persistence — clarification

`EpogArmoryDB` is declared in the TOC as `## SavedVariables: EpogArmoryDB, EpogItemCacheDB` (capital S = account-scope). It IS shared across all characters on the same WoW account. If you set `/epogarmory main Defcon` while playing Defcon and later log in as Defcoil, the main is still set to Defcon. The v0.43 behavior was correct; the new display message just makes that clearer.

---

## EpogArmory v0.43 — Sender-side level gate + main-name identity *(2026-04-26)*

Two changes that together solve the "alt pollution" problem in the mesh.

### 1. Sender-side level gate

`TryScanSelf` now checks `UnitLevel("player") < MIN_STORE_LEVEL` (60) and silently skips the scan + broadcast. Receivers' `ShouldStore` already rejected level < 60, but the broadcast still went out — every guildmate's debug log saw `[store] REJECT: <name> L33 — level 33 < 60` for every alt-broadcast cycle. Now the broadcast doesn't happen at all on low-level alts. Mirrors the existing `MIN_INSPECT_LEVEL` gate on the inspect-other path.

### 2. Main-name identity

New config field `EpogArmoryDB.config.mainName` — when set, all your broadcasts attribute to this name rather than the live character. So scans from your alts consolidate under one identity in everyone's Scanners view, and an admin can `syncfrom <main>` to reach you regardless of which alt you're playing.

**Slash command:**

```
/epogarmory main                      — show current + list known characters
/epogarmory main <characterName>      — set (must be a character you've logged in on)
/epogarmory main clear                — revert to using current character name
```

The choice is **restricted to characters you've actually logged in on this account**. SavedVariables is account-scoped, so each `PLAYER_LOGIN` adds the current character to `EpogArmoryDB.knownChars`. The slash command validates against this set — typing a name you've never logged in as is rejected with the list of valid choices.

**Wire format addition (position 39):** every outbound scan payload carries the broadcaster's main name (or empty string when not configured). Append-only per the v0.7 rule — old clients ignore it. Receivers extract `entry.senderMain` and use it as the canonical scanner identity:

- `set.scannedBy` on stored entries — main name when present, sender character name as fallback
- `EpogArmoryDB.peerInfo` is now keyed by main name (not character name), with a new `lastCharName` field tracking the most recent broadcasting alt for reachability lookups
- The Scanners view aggregation, ranking, and click-to-sync all work against the consolidated identity

**SYNCREQ routing:**
- Outgoing `requester` field uses `MyIdentity()` (main name or character name fallback) — per-requester cooldowns now span all your alts
- Incoming target check accepts `target == UnitName("player")` OR `target == config.mainName` — admin can send `syncfrom Defcon` and reach Defcon's currently-logged-in alt regardless of character

**Reachability:** `BuildReachableSet` now also resolves main-name keys through `peerInfo.lastCharName` — if the peer's last-broadcasting alt is in your guild/group, the main-name row is reachable.

**Behavior with no main configured:** identical to v0.42. The wire field stays empty, receivers fall back to character names everywhere, no consolidation happens. Set the main name to opt in.

---

## EpogArmory v0.42 — Fix Players-view rows staying dim after Scanners visit *(2026-04-26)*

User reported greyed-out names in the Players view that didn't correlate with class colors or any other state. Cause: the Scanners view's reachability dimming (`row:SetAlpha(0.55)` for offline peers) was leaking back into Players view because `UpdatePlayersMode` never reset row alpha. Whichever rows were dim in the last Scanners render stayed dim when the user toggled back to Players.

Fix: explicit `row:SetAlpha(1.0)` in both branches of `UpdatePlayersMode` (populated row + empty row). No other behavior change.

For reference — the **age column color** in the Players view is intentional and unchanged:

| Color | Age range |
|---|---|
| Green | < 1h ago |
| Yellow | < 24h ago |
| Gray | ≥ 24h ago |

That's `AgeColor()` from v0.21. The bug was only on the **name** column where alpha was bleeding through.

---

## EpogArmory v0.41 — Remove zone restriction *(2026-04-24)*

Dropped the instance-only scanning gate. Previously scans were only captured inside dungeons/raids ("requireInstance = true" default); now they capture anywhere — outdoor world, BGs, arenas, cities, everywhere.

Rationale: the restriction existed as a safety net against "bank alt in town wearing fun gear" scenarios, but that role is now covered properly by:

- **Mount-gear filter** rejects scans with Carrot on a Stick / Riding Crop / Charm of Swift Flight / Argent War Horn / fishing poles / Chef's Hat / Rugged Sandle / Mithril Spurs enchant / Riding Skill glove enchant
- **PvP set routing** — Insignia trinkets now flag the scan as a PvP loadout and route to `sets["pvp"]` instead of polluting the main spec sets
- **Per-spec storage** — even if an unusual loadout is captured, it lands in its own dominant-tree or PvP slot without overwriting other sets
- **4h mesh cooldown** — no flood of scans even with the gate removed

Net effect: arena/BG/open-world/city scans now land in the armory. Raid leaders can inspect PUGs outside the instance. PvP testers get real data.

**Removed:**
- `requireInstance` variable + all 4 zone gates (`ShouldStore`, `AddUnit`/`ScanRoster`, `TryInspect`, `TryScanSelf`)
- `IsInstanceZone()` helper (no longer needed)
- `/epogarmory instance on|off` slash command
- "requireInstance=" field from `/epogarmory status` output
- Help-listing lines advertising the command

**Kept:**
- `ZoneType()` — still used to populate `entry.zone` as informational metadata on each set (site armory can show "scanned in raid"/"arena"/"outdoor")
- `InCombatLockdown()` gates on `TryInspect` and `TryScanSelf` — combat-safety is unchanged

**Config:** any lingering `EpogArmoryDB.config.requireInstance` from old installs is cleared to nil on login (vestigial field, does nothing).

---

## EpogArmory v0.40 — Dedup tooltip stats against GetItemStats *(2026-04-24)*

Modern items were getting the same stat captured twice — once from `GetItemStats` into `entry.stats` and again from tooltip pattern-matching into `entry.tooltipStats`. User example:

```lua
[12930] = { -- Briarwood Reed
    stats = { ITEM_MOD_SPELL_POWER_SHORT = 29 },
    tooltipStats = { SPELL_POWER_FLAT = 29 },  -- duplicate
}
```

Site would render "+29 Spell Power" twice. Fix: new `TOOLTIP_STAT_REDUNDANT_WITH` map lists tooltip keys that have an equivalent `ITEM_MOD_*` in the GetItemStats enum. When the tooltip scanner matches one of those patterns AND the equivalent is already present in `entry.stats`, the tooltip capture is silently skipped.

Mapping:

| Tooltip key | GetItemStats equivalent |
|---|---|
| `SPELL_POWER_FLAT` | `ITEM_MOD_SPELL_POWER_SHORT` |
| `HEALING_FLAT` | `ITEM_MOD_SPELL_HEALING_DONE_SHORT` |
| `SPELL_DAMAGE_FLAT` | `ITEM_MOD_SPELL_DAMAGE_DONE_SHORT` |
| `MP5` | `ITEM_MOD_MANA_REGENERATION_SHORT` |
| `HP5` | `ITEM_MOD_HEALTH_REGEN_SHORT` |
| `DEFENSE_FLAT` | `ITEM_MOD_DEFENSE_SKILL_RATING_SHORT` |
| `SPELL_PENETRATION_FLAT` | `ITEM_MOD_SPELL_PENETRATION_SHORT` |
| `BLOCK_VALUE_FLAT` | `ITEM_MOD_BLOCK_VALUE_SHORT` |

Percent-based keys (CRIT_*_PCT, HIT_*_PCT, DODGE_PCT, etc.) and per-school spell damage (SPELL_DAMAGE_FIRE etc.) are NOT in the GetItemStats enum on any item, so they always flow to `tooltipStats` without a redundancy check. Same for Ascension PvP stats (DAMAGE_VS_PLAYERS_PCT).

**Pre-rating items unaffected.** A vanilla/TBC item with "+29 Damage and Healing" that GetItemStats doesn't know about still gets `tooltipStats.SPELL_POWER_FLAT = 29` — the dedup only fires when BOTH would be present.

**Line-consumed semantic preserved.** Even when the tooltip match is dedup-skipped, the scanner still marks the line as "matched" so it doesn't then leak into `tooltipExtras`. No collateral.

**Schema bump v9 → v10** so existing v9 entries with duplicates re-fetch and apply the dedup on next touch. `/epogarmory cachewipe && cachebuild` to force-refresh eagerly; otherwise it happens gradually as scans flow.

---

## EpogArmory v0.39 — Fix PvP-set ingest crash (%d on string group key) *(2026-04-24)*

Critical bugfix — Ingest crashed on any PvP-flagged scan.

Two `string.format` calls in `Ingest` used `%d` to format the group key, which worked fine when group was numeric (1/2/3 for class trees) but threw `bad argument #4 to 'format' (number expected, got string)` when group was `"pvp"` (introduced in v0.33). Result: every PvP scan raised a Lua error, the store path aborted, and no PvP data landed in `EpogArmoryDB`.

The bug was silent unless you had the default error popup enabled or were running BugSack — explains why v0.33+ testers who weren't wearing Insignia didn't see it, but anyone with a PvP loadout crashed on every self-scan.

Two lines changed — `%d` → `%s` on the group format specifier, wrapped with `tostring(group)` to be safe against future key types:

```lua
-- Before (v0.33 through v0.38):
"[store] OK: %s L%d [tree %d / %s]" , entry.name, entry.level, group, entry.zone
-- After (v0.39):
"[store] OK: %s L%d [set %s / %s]", entry.name, entry.level, tostring(group), entry.zone
```

Same fix on the SKIP-log branch when an older scan for the same set arrives.

---

## EpogArmory v0.38 — Scanners view polish: leaderboard + reachability + UI fixes *(2026-04-24)* *(local-only, not released yet)*

Five refinements from user testing feedback on v0.37:

**1. Accept-sync checkbox text now hides with the button.** In v0.37 the label FontString was parented to the browser frame itself (`f:CreateFontString(...)`), so `acceptSyncBtn:Hide()` only hid the checkbox, not the label — the text "Accept sync requests from others" stayed visible in Players mode. Re-parented the FontString to the button itself so both hide together.

**2. View-mode toggle moved to top-left.** Was at top-right below the close button (cramped). Now at `TOPLEFT +14, -14` — cleaner hierarchy, doesn't compete with the close X.

**3. Reachability check on Scanners rows.** Peers who are offline, not in your guild, and not in your party/raid can't respond to a SYNCREQ — so they now render dim (alpha 0.55, grey name) and clicking them prints a chat message instead of opening the confirm popup. The reachability set is built fresh on every Update via:
  - `GetNumPartyMembers` + `UnitName("partyN")` for party members
  - `GetNumRaidMembers` + `UnitName("raidN")` for raid members
  - `GetGuildRosterInfo` iteration for guildmates with `online == true`

`GuildRoster()` is called on mode switch into Scanners and on the 30s ticker to keep the online flag fresh (server rate-limits the RPC ~10s, so spamming is harmless). Footer adds an "(N online)" count.

**4. Leaderboard numbering.** Each Scanners row now prepends `#N` where N is the rank (sorted by peer-reported DB size → scannedBy contribution as fallback). Numbers stay stable through pagination (`#1` is always the highest, `#25` is the 25th even if you've scrolled).

**5. Scroll future-proofing.** Both views already used `FauxScrollFrame_Update` + offset paging, so arbitrary list sizes have always worked — but the scroll frame didn't have mousewheel enabled by default. Added `EnableMouseWheel(true)` + an `OnMouseWheel` handler (3 rows per tick). Works in both Players and Scanners view.

Also bumped the 30s ticker from "refresh only when syncs active" to "refresh always in Scanners mode" — so peers coming online / offline, new broadcasts updating peerInfo, and roster joins all reflect live without manual toggle.

---

## EpogArmory v0.37 — Sync on raid/party + 3-concurrent cap + syncoff toggle *(2026-04-24)* *(local-only, not released yet)*

Three changes: extend sync to raid/party channels, cap concurrent syncs to 3 with visible timers, and add a syncoff toggle (default on).

### 1. Channel extension

`/epogarmory syncfrom` now broadcasts on every available channel — `PickChannels()` returns whichever of `RAID`/`PARTY` applies plus `GUILD`. `HandleSyncRequest` accepts `GUILD`, `PARTY`, and `RAID`; whisper and battleground stay rejected.

If the target is in both your guild and your raid, they receive two copies of the SYNCREQ; the first triggers the response, and the per-requester cooldown makes the duplicate a no-op.

### 2. Requester-side 3-concurrent cap

New constants `SYNC_MAX_CONCURRENT = 3` and `SYNC_EST_DURATION = 25*60`. New in-memory `activeSyncs[peerName] = estimatedEndTime` tracker.

Behavior:
- `/epogarmory syncfrom <name>` rejects (chat message) if you already have 3 active, or if you're already syncing from this specific peer
- In the Scanners view, active-sync rows render dimmed (alpha 0.55) with `"syncing... (~Xm left)"` instead of DB size
- When 3 are active, ALL remaining rows dim — click shows an explanatory chat line instead of the confirm popup
- Footer reads `"N scanners · click to sync (K/3 active)"` or `"sync limit reached"` at cap
- Browser ticks every 30s while a sync is active so the countdown stays fresh

### 3. Responder-side defense: syncoff toggle + global cooldown

Two protections against sync-bomb scenarios:

- **`EpogArmoryDB.config.acceptSync = true`** (default). Toggle via `/epogarmory syncoff` / `syncon`, OR via the new checkbox "Accept sync requests from others" in the Scanners view (bottom-left). When false, all incoming SYNCREQ are declined with a debug line.
- **`SYNC_GLOBAL_COOLDOWN = 900` (15 min)** — regardless of requester, responds to at most one SYNCREQ every 15 min. Caps outQueue drain at a single 20-min response even under a 10-attacker bomb.

### Bomb-scenario math

| Scenario | Before v0.37 | After v0.37 |
|---|---|---|
| 10 attackers bomb you, 10 unique requesters | Up to 10 × 20 min = ~3h drain | 1 × 20 min = 20 min |
| 1 attacker loops `syncfrom` | Blocked by 1h per-requester cooldown | Same (unchanged) |
| Admin syncs 3 peers legitimately | 3 × 20 min parallel on each target | Same — global cooldown is per-responder, not requester-set |
| 4th sync attempt as admin | Fires a 4th outbound stream | Rejected until one of the 3 active finishes |

### UI surface exposed

New fields on `_G.EpogArmory`:
- `IsPeerSyncActive(name)` — returns boolean, checks in-memory activeSyncs
- `SyncEndTimeFor(name)` — returns the estimated end timestamp, or nil
- `ActiveSyncCount()` — returns count of active syncs
- `SyncMaxConcurrent` — constant (3)

### Persistence

- `EpogArmoryDB.config.acceptSync` survives `/reload` and logout
- `activeSyncs` is in-memory only — `/reload` wipes it, which correctly matches `/reload` also wiping the `outQueue` that was draining responses

---

## EpogArmory v0.36 — Browser Scanners view + peer DB-size broadcast *(2026-04-24)* *(local-only, not released yet)*

Pair of changes that together answer "who should I sync from?":

### 1. Browser gains a Scanners view

Toggle button top-right of the browser (next to the close button). Click to flip between:

- **Players mode** (default) — the existing searchable list of scanned players
- **Scanners mode** — a leaderboard of peers sorted by "how much data they have to share", rows clickable to trigger a `syncfrom`

Clicking a scanner row pops a confirmation (`"Request a sync from <name>? They'll replay their last 7 days of scans over guild chat. Drain takes ~20 minutes."`). Confirm fires `/epogarmory syncfrom <name>` — same path the hidden slash command uses. Peers still respect the 1-hour per-requester cooldown, so accidental double-clicks don't spam them.

Empty-state hint switches per mode — Players mode tells you to scan groupmates; Scanners mode tells you the view fills in as guildies broadcast.

### 2. DB size piggybacked on every broadcast

Each outbound scan payload now carries the sender's own `EpogArmoryDB.players` count as a single integer at wire position 38. Receivers stamp `EpogArmoryDB.peerInfo[sender] = { dbSize, lastSeen }` on ingest. No new protocol — just one more field on the existing scan payload, additive per the append-only wire rule.

Scanner view uses this as the primary ranking signal ("reported X in DB, heard Y ago") and falls back to a scannedBy-contribution count when a peer hasn't broadcast in the current session. So the view is immediately useful on login without needing fresh mesh traffic, and becomes more accurate as peers' broadcasts flow through.

### Persistence

`EpogArmoryDB.peerInfo` is a SavedVariables table, so the ranking survives `/reload` and logout. On first install it's empty — fills in as peers do normal scans.

### Traffic cost

~5-10 bytes per broadcast payload (one small integer + separator). Absolutely negligible against the existing 500-byte payload size. Old receivers (v0.35 and earlier) silently ignore the new position-38 field per the append-only rule.

---

## EpogArmory v0.35 — Hidden admin sync (`/epogarmory syncfrom`) *(2026-04-23)* *(local-only, not released yet)*

The mesh is gossip-only — guildies' accumulated DBs never replay to you after a break. Problem for the admin who uploads SavedVariables to epoglogs: they need everyone's data in their own local DB, but the mesh only feeds them live scans.

**New hidden slash command:**

```
/epogarmory syncfrom <playerName>           — request last 7 days from a peer
/epogarmory syncfrom <playerName> 30        — last 30 days
/epogarmory syncfrom <playerName> 0         — everything the peer has
```

Not listed in `/epogarmory help` — this is an admin tool, not a general feature.

**Protocol:**

- Requester broadcasts `SYNCREQ^<requesterName>^<targetName>^<sinceTimestamp>` over the GUILD channel (single chunk).
- Every peer receives the request. Most ignore it (the target name doesn't match their character). The named target checks:
  - Request arrived on `GUILD` channel (not PARTY/RAID/whisper — prevents cross-channel abuse)
  - They haven't already responded to this requester within the last hour (`SYNC_RESPONSE_COOLDOWN = 3600`)
- If both checks pass, the target iterates their stored `players[].sets[].rawPayload`, filters by `scanTime > sinceTS`, and replays up to 200 payloads (`SYNC_MAX_SETS_PER_RESPONSE`) through the normal outQueue.
- At the standard 2s broadcast stagger × 3 chunks per payload, 200 payloads drain in ~20 minutes. Cap prevents multi-hour drains even for huge DBs.
- Other guildmates ingest the replays too — free benefit: their DBs catch up alongside the admin's.

**Storage change:** each set now carries `set.rawPayload` — the verbatim wire payload we received. Using the raw string instead of reconstructing via a sibling `BuildPayloadFromStored` helper avoids drift as the wire format evolves. Every new Ingest stamps it; legacy v0.34- sets without `rawPayload` won't be replayed on sync (but will fill in on next re-scan).

**Rate-limiting protections:**

- Per-requester cooldown (1h) on the target side prevents one requester from looping sync requests
- 200-set cap bounds any single response
- Guild-channel-only gate prevents someone whispering a SYNCREQ and triggering response via a private channel

**Typical admin flow for pre-upload sync:**

```
/epogarmory syncfrom Alice          -- start with your most active guildie
  ... wait ~20 min for drain ...
/epogarmory syncfrom Bob 30         -- another peer, last 30 days
  ... wait ...
/epogarmory syncfrom Charlie 0      -- fetch everything Charlie has
  ... wait ...
/epogarmory cachebuild              -- warm the item cache across all new entries
/logout                             -- flush SavedVariables to disk
# then upload WTF/Account/<ACCT>/SavedVariables/EpogArmory.lua to epoglogs.com
```

Not a full history replay (gated by the 200-set cap and the per-peer `rawPayload` availability), but good enough for an admin to stay near-current without needing file-copy coordination.

**Local impact on peers:** a typical response fully drains the responder's outQueue for ~20 minutes. Their own legitimate scan broadcasts queue up behind the sync replay and go out after. No data loss, just delayed delivery during the sync window. Peers should see a single `[sync]` debug line when they respond (if they have debug on), otherwise silent.

---

## EpogArmory v0.34 — Shorter inspect cooldown for groupmates (4h) *(2026-04-23)* *(local-only, not released yet)*

v0.33 added PvP set detection, but the pre-existing 24h per-GUID inspect cooldown meant an in-raid swap from Combat PvE → Insignia PvP wouldn't be captured until the next day. For raid leaders checking who's mid-swap, that's too slow.

Fix: **`SCAN_FRESH_WINDOW` reduced from 86400 (24h) to 14400 (4h).** Since `AddUnit` is only called from `ScanRoster`'s party/raid iteration, every candidate is already a groupmate by definition — so shortening this one constant is exactly the "group-only 4h refresh" behavior with no extra bookkeeping.

**Traffic:** ~6× previous (one inspect per target per 4h instead of per 24h). The shared mesh-wide `lastScanned` still coordinates between clients — when one installer inspects Bob, every peer's 4h timer resets in sync, so traffic converges to "one broadcast per target per 4h across the whole mesh". For a 40-player raid where everyone gets re-inspected, that's roughly ~1 minute of per-target per-day broadcast drain. Acceptable and well under the addon-message throttle.

**Why not per-client tracking?** I originally sketched a separate `lastLocalInspect[guid]` table but realized it'd make every new installer trigger a fresh full scan of all mesh-known targets (their local timer starts empty). That's an O(N) traffic spike per installer join. The shared `lastScanned` path is strictly better — same coverage, traffic scales with activity not with installer count.

**Self-scan unchanged.** Your own character still uses fingerprint dedup; this only affects inspecting other players.

**Resets unchanged:** `/epogarmory wipe` still clears the whole `lastScanned` table; the per-player Delete button still clears `lastScanned[guid]` for that player.

---

## EpogArmory v0.33 — PvP loadout detection + 4th spec button *(2026-04-23)* *(local-only, not released yet)*

Insignia trinkets have been rejected entirely since v0.13 (utility-loadout filter). That's been correct for "don't let a PvP scan clobber the PvE gear" but wrong for "this is my actual combat loadout and deserves its own row in the armory". v0.33 flips the behavior:

**Detection:** an item with `"Insignia"` in the name equipped in slot 13 or 14 flags the whole scan as a PvP loadout. Both sender (`UnitLooksPvP`) and receiver (`EntryGearLooksPvP`) run the same check independently — robust against version mismatch between peers.

**Storage:** the scan lands in `player.sets["pvp"]` alongside the existing `sets[1]` / `sets[2]` / `sets[3]` dominant-tree keys. Same shape, just a new key type (string instead of integer). No DB migration needed — existing entries keep their talent-tree sets, new PvP scans fill in the `"pvp"` slot.

**UI:** inspect frame now has 4 spec buttons instead of 3. Layout tightened from width=90 to width=72 per button to fit 4 across in the 320-wide frame; class-tree names longer than 10 chars auto-truncate with a trailing dot (`"Assassination"` → `"Assassinat."`). The PvP button always reads `"PvP"` — no class-dependent label. When the PvP set is rendered, the centerpiece spec icon switches to the same `INV_Shield_06` the minimap uses.

**Filter change:** `UTILITY_ITEM_NAMES_BY_SLOT` no longer rejects Insignia — the filter kept catching real PvP combat loadouts people wanted archived. Other filters unchanged (fishing poles, mount-speed enchants, Rugged Sandle, etc. still reject).

**Wire format:** position 31 now carries a string group key — `"1"` / `"2"` / `"3"` for class trees or `"pvp"` for PvP. Receivers ignore the wire value and compute their own group locally (per the forward-compat rules), so the wire field is informational. Old receivers (v0.32-) still reject Insignia scans on the old utility filter — they won't ingest PvP scans from new senders. That's acceptable: eventual consistency as users upgrade via the version-ping nudge.

**Schema unchanged** — `EpogItemCacheDB` shape is the same (no v9→v10 bump). The only data-model change is in `EpogArmoryDB.players[guid].sets` where the key set expands from `{1,2,3}` to `{1,2,3,"pvp"}`. Lua tables handle mixed numeric/string keys natively.

**Tested scenarios:**
- Player with only PvE gear in all three trees → 3 buttons lit, PvP dimmed
- Player with only PvP gear scanned → only PvP button lit, 3 trees dimmed
- Player with Combat PvE + PvP → 2 buttons lit (Combat, PvP), Assassination/Subtlety dimmed
- Player wearing Insignia and scanned in a raid instance → set routes to PvP, not sets[DominantTree]
- Pre-v0.33 cached player scanned under the old filter → no PvP data yet; next scan while wearing Insignia fills sets["pvp"]

---

## EpogArmory v0.32 — Filter stat-like `Equip:` lines + codify compat rules *(2026-04-23)* *(local-only, not released yet)*

Two things:

**1. Stop duplicating flat stats into `tooltipExtras`.**

After v0.31 fixed the prefix-check bug, `Equip:`-prefixed lines started flowing into `tooltipExtras` as intended — but the fall-through rule (accept any unmatched `Equip:` line) was too broad. Hand of Justice was landing with `stats.ITEM_MOD_ATTACK_POWER_SHORT = 20` AND `tooltipExtras = { "Equip: +20 Attack Power." }` — the same +20 AP would render twice on the site's armory tooltip (once from `stats`, once from the verbatim extras line).

Added `IsStatLikeEquipLine(text)` filter. `Equip:` lines matching any of these shapes get skipped:

- `"Equip: +N <stat>..."` (e.g. `"+20 Attack Power."`)
- `"Equip: Increases [your] <stat> by N."`
- `"Equip: Decreases your <stat> by N."`
- `"Equip: Restores N <resource> per 5 sec."`

Proc/effect lines don't match any of these shapes (they contain `"chance"` / `"on hit"` / `"for N sec"` / etc.), so they continue to flow through to extras unchanged. Hand of Justice's `"Equip: 2% chance on melee hit to gain 1 extra attack."` still lands in `tooltipExtras` as expected.

**Schema bump to v9** so v8-cached items re-fetch and the duplicated stat-like Equip lines drop out of their `tooltipExtras`.

**2. Documented the forward-compatibility contract in-code.**

Added a comment block at the top of `EpogArmory.lua` (just above `PROTO` declaration) codifying:

- The three guarantees: append-only wire format, PROTO leniency, item data is local/not transmitted
- The three rules: never reorder positions, never change field semantics, never remove fields
- The escape hatch: PROTO bump with dual-broadcast transition window for genuinely-breaking changes
- Pointers to `MigratePlayers` for `EpogArmoryDB` shape changes and `CACHE_SCHEMA` for `EpogItemCacheDB`

This is for future-me and any future contributors. The rules have all been followed so far, but having them written down in the code near the wire-format definitions makes it obvious where the landmines are before anyone touches them.

---

## EpogArmory v0.31 — Fix broken `tooltipExtras` prefix check *(2026-04-23)* *(local-only, not released yet)*

Fresh bug — the `tooltipExtras` prefix filter was a no-op. User reported Hand of Justice and Felstriker had `stats` + `damage` + `speed` populated correctly but `tooltipExtras` was absent entirely, even though both items have obvious proc lines (`"Equip: 2% chance on melee hit to gain 1 extra attack."` and `"Chance on hit: All attacks are guaranteed to land..."`).

Root cause — classic Lua-pattern confusion. The check was:

```lua
if text:find("^" .. prefix, 1, true) then
```

The `plain = true` 4th arg tells `string.find` to treat the pattern as a literal substring, which disables metacharacters — so the `^` stopped being a start-anchor and became a literal caret character. The search was looking for `"^Chance on hit:"` (8 chars including `^`) anywhere in the tooltip, which never matches anything.

Silent since v0.28 because the control flow was "if the check matches, add to extras", and the check never matched, so we just never captured extras. All v5, v6, v7 schema entries that should have had extras have none. Every Eskhandar / HoJ / Felstriker / trinket with a proc was missing its flavor text.

Fix: replace with `text:sub(1, #prefix) == prefix` — plain substring compare, no pattern-escape concerns, unambiguously anchored at position 1.

**Schema bump to v8** so all v7-cached items (which have the bug-empty extras field) get re-fetched and pick up the correct capture. `/epogarmory cachewipe && cachebuild` recommended for immediate fix-up across all stored items.

Expected post-v0.31 cache for Hand of Justice:

```lua
[11815] = {
    v = 8,
    name = "Hand of Justice",
    stats = { ITEM_MOD_ATTACK_POWER_SHORT = 20 },
    tooltipExtras = {
        "Equip: Increases attack power by 20.",
        "Equip: 2% chance on melee hit to gain 1 extra attack.",
    },
}
```

(Note the duplication of AP between `stats.ITEM_MOD_ATTACK_POWER_SHORT = 20` and the first `Equip:` line — this is the accepted side effect of the v0.30 fall-through rule. Site-side can dedup.)

---

## EpogArmory v0.30 — Weapon damage + speed + `Equip:` extras *(2026-04-23)* *(local-only, not released yet)*

Two gaps surfaced from epoglogs v0.28.1 real-user testing:

**1. Weapon damage range + speed.** `GetItemStats` exposes DPS (`ITEM_MOD_DAMAGE_PER_SECOND_SHORT`) but not min/max damage range or attack speed. Armory tooltip was rendering `(40.0 damage per second)` with no `X - Y Damage` or speed line above it — the core of any weapon tooltip was missing.

Added tooltip-line parsers:

```lua
entry.damage = { min = 9,  max = 17 }               -- plain physical
entry.damage = { min = 12, max = 19, school = "Holy" }  -- elemental
entry.speed = 2.80                                   -- seconds between swings
```

`ParseDamageLine` matches `^(%d+)%s*%-%s*(%d+)%s+(%a*)%s*Damage$` — handles both `"9 - 17 Damage"` and `"12 - 19 Holy Damage"`. `school` is nil for plain physical.

`ParseSpeedLine` matches `Speed%s+(%d+%.?%d*)` anywhere in the line — WoW renders speed on either column (next to the equip-slot label), so the scanner checks both left and right text of each tooltip line.

**2. `Equip:` proc lines falling through.** `Chance on hit:` and `Use:` were already captured to `tooltipExtras`, but the most common proc carrier — `Equip:` — was deliberately excluded in v0.28 to avoid duplicating stat lines like `"Equip: Increases attack power by 15."` into extras.

That exclusion was too aggressive. Real-user items affected: Hand of Justice ("Equip: 2% chance on a successful melee attack to increase your attack power by 300 for 15 sec."), Eskhandar's Collar, Eskhandar's Razor, Deathbringer's Will. Fix: add `"Equip:"` to the `TOOLTIP_EXTRA_PREFIXES` whitelist. The existing fall-through guard (`if not matched`) still applies — stat lines consumed by `TOOLTIP_STAT_PATTERNS` don't reach the extras check.

Accepted side effect: items with Equip-prefixed flat stats ("Equip: Increases attack power by 15." — caught by GetItemStats but not by my tooltip patterns) will have their raw text duplicated into `tooltipExtras`. Site-side can dedup by matching the numeric value against `stats`.

**Schema bump to v7** so v6-cached items re-fetch and pick up `damage`, `speed`, and the expanded `tooltipExtras`. `/epogarmory cachewipe && cachebuild` on upgrade for eager refresh.

**Server-side ready.** epoglogs v0.28.1 already consumes `damage` (currently stopgap'd from TDB retail) and `tooltipExtras` (renders any string the addon emits). `speed` is a new field — needs a one-line addition to `buildItemMeta`. Otherwise fully transparent: once addon-captured fields land in the upload, they override TDB automatically via the existing priority pattern.

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
