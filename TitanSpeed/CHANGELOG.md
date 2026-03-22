# TitanSpeed — Changelog

## v1.0 — Initial Release

- Titan Panel plugin displaying player movement speed as a percentage
- Detects active speed buffs: Druid forms, Sprint, Ghost Wolf, mounts, speed potions
- Shows yards/sec and active speed sources in tooltip
- Polls every 0.2 seconds via `OnUpdate`
- **Speed buff display:** tooltip shows each active speed buff with its bonus percentage, e.g. `Cat Form (+30%)`, `Sprint (+70%) - 9s`; rank-varying spells (Sprint, Dash) resolve the correct % from the rank string returned by `UnitBuff`; timed buffs show remaining seconds
