# EpochSynch

A World of Warcraft 3.3.5 (Project Epoch) battleground addon that gives you **cross-map visibility of
your team** — broadcasting each teammate's health, mana, and position so you can read the whole
battleground at a glance, even players on the far side of the map.

## Features

- **Shared roster** — every player running the addon broadcasts their HP/MP/position over addon
  messages, so everyone sees everyone.
- **Multiple views** — teammates (and tracked enemies) rendered on the **minimap**, the **world map**,
  and a compact class-coloured **roster** panel.
- **Compact wire protocol** — a slow channel for identity (name / class) and a fast channel for live
  HP/MP/position, kept small to stay within addon-message size limits.
- In-battleground raid-frame compatibility override.

## Structure

- `Core/` — the engine, the broadcast/parse protocol, and roster state (`Engine.lua`, `Protocol.lua`,
  `Enemy.lua`).
- `UI/` — `Minimap.lua`, `WorldMap.lua`, `Roster.lua`.

## Install

Drop the `EpochSynch` folder into your `Interface/AddOns/` directory.

## License

[GPL-3.0-or-later](LICENSE) — © Defcon.
