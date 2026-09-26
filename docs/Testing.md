# epoch-addons — Pending Tests (unconfirmed)

_Holds ONLY what is not yet human-verified, with cold-runnable repro steps + pass
criteria. Confirmed → graduate the result to KnowledgeBase/ResearchJournal, then
delete the entry._

_Last verified: 2026-08-20 @ 6f85371 — seeded from the long-open EpochFixes question._

## 1. EpochFixes — are its four patches actually working in-game?

**Why:** the addon is self-flagged "not working as intended — issues may be
server-side" (KB §7/§9); open since ≤2026-08-03. Nothing here is confirmed live.

**Machine-verified already:** code present and loads (v1.1.0, Interface 30300,
`/epochdebug` slash registered); all four hooks exist in `EpochFixes/EpochFixes.lua`.
NOT verified: in-game effect of any patch.

**Setup (all steps):** log into Project Epoch with EpochFixes enabled
(`/epochdebug` responds ⇒ loaded). Run with pfQuest enabled too (patches 3–4
specifically defend against its tooltip theft).

1. **Spellbook crash guard** — open the spellbook, hover tab 2 repeatedly.
   PASS: no Lua error / crash.
2. **Quest-abandon selection drift** — with 5+ quests in the log, click Abandon on
   quest A, wait 2–3 s on the confirm popup (let QUEST_LOG_UPDATE fire), confirm.
   PASS: quest A (not another quest) is abandoned. Repeat ~5 times.
3. **Quest-reward tooltips** — at a quest turn-in with item rewards, hover each
   reward. PASS: tooltip anchors to the reward button (not stolen/misplaced).
4. **Inspect-cache expiry** — inspect a player, wait >15 s, hover their gear slots.
   PASS: item tooltips still show (cached links) instead of empty tooltips.

**On verdict:** record per-patch results in ResearchJournal; if some patches are
dead server-side, downgrade/annotate KB §9 EpochFixes and decide keep-vs-strip in
ToDo. Then delete this entry.
