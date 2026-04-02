# unitscan (v1.0)

Originally by shirsig, tablegrapes & Sattva. Modified for **WoW 3.3.5a (Ascension/Epoch)** by Defcon — uses independent version history.

## Features

- Scans for configured rare mobs and shows a popup when one is detected nearby
- **Dead mob cooldown tracking** — mobs confirmed dead are put on respawn cooldown and skipped from scanning; reads respawn time from pfQuest's unit database when available, falls back to configurable default (8 hours)
- **pfQuest map icon integration** — removes the rare's map pin when it dies; hides it on every map refresh while cooldown is active; restores automatically when cooldown expires
- **Instance dismiss cooldown** — closing the popup inside an instance applies a 1-hour cooldown so the mob won't alert again for the remainder of the session
- **Combat-safe close button** — uses `SecureHandlerClickTemplate` so the popup can be dismissed during combat lockdown
- **Combat guard** — `UPDATE()` returns early when `InCombatLockdown()` to prevent `ADDON_ACTION_BLOCKED` spam

## Slash Commands

| Command | Action |
|---|---|
| `/unitscan` | Open configuration |
| `/unitscan cooldowns` | List all mobs on dead cooldown with time remaining |
| `/unitscan cooldown <hours>` | Set fallback respawn cooldown for mobs not in pfQuest |

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
- Optional: **pfQuest-wotlk** for accurate per-mob respawn times and map icon management
