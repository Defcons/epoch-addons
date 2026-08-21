# BuffWatcher

A raid **buff & consumable checker** for World of Warcraft 3.3.5 (Project Epoch). At a glance it shows
who in your raid is missing buffs, flasks, or food — organised by combat role.

## Features

- **Per-role buff lists** — separate Tank / Healer / Melee / Ranged checklists, each fully editable.
- **Talent-based spec detection** — reads each player's talents (`GetTalentTabInfo` for you, an inspect
  queue for the rest of the raid) to assign the correct role automatically, with manual overrides.
- **Status window** with a Role column and a TSV export of who's missing what.
- Slash commands: `/bw`, `/bw config`, `/bw check`, `/bw export`, `/bw inspect`.

## Install

Drop the `BuffWatcher` folder into your `Interface/AddOns/` directory.

## License

[GPL-3.0-or-later](LICENSE) — © Defcon.
