# ToDo — epoch-addons

_Deferral ledger: the moment anything is set aside / deferred / decided-not-now, it
gets an entry here. Done → check off, prune on next touch. Human-test-only items
live in `Testing.md`, never mirrored here._

_Last verified: 2026-08-20 @ 6f85371 — seeded from repo state during the bible pass._

## Open

- [ ] **Distill EpogArmory internals into KB §9 + OrientationMap** — the flagship
  (~51% of code history, v2.0.2) has no per-addon deep notes: files, SavedVariables
  schema, and the dummy-parse marker round-trip are undocumented outside git.
  (KB §5 UNKNOWN; open since the 2026-08-03 Journal pass.)
- [ ] **Add `!Postal/` to the `.gitignore` allowlist** — `Postal/Modules/OpenAll.lua`
  is tracked, but without an allowlist entry any NEW file under `Postal/` is
  silently ignored. (Found 2026-08-20 comparing `git ls-files` vs `.gitignore`.)
- [ ] **Add EpogArmory + Postal rows to `README.md`'s catalog** — both are absent
  from the user-facing addon list (EpogArmory is the flagship; verified 2026-08-20).
- [ ] **EpochSimData (ESD) is untracked in ANY git repo** — single copy at the game
  install path (`…\Interface\AddOns\EpochSimData\`, see OrientationMap §ESD),
  ~1400-line addon + analysis scripts with no version control or backup. Decide:
  whitelist it into this repo (or another) vs. accept the loss risk.
- [ ] **Live install checkout carries uncommitted work** (seen 2026-08-20):
  modified `Aux-addon/aux-addon.toc` + `tabs/search/frame.lua` + `tabs/search/results.lua`,
  `TradeSkillMaster_Crafting/Modules/CraftingGUI.lua`, `pfQuest-epoch/{CHANGELOG.md,README.md,*.toc}`.
  Review in the install checkout: commit (with CHANGELOG entry) or discard. Also
  delete its stale `claude/romantic-knuth-22587d` branch (behind origin/master by 35).

## Blocked / needs the user

(nothing yet)

## Done (prune on next touch)

(nothing yet)
