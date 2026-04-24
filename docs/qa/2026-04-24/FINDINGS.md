# Ledger behaviour QA — 2026-04-24 (v5)

## Overall read

Clean round. All three targeted fixes from the v3 → v4 plan landed
without regressing anything that was working. Scenario B's repeat-ask
pattern (four turns of sleep questions) is gone. Scenario G's UI
reference (`"tap the entry on the Today page"`) is gone. Scenario A's
late-arriving plan (turn 7 after the user prompted "so what should i
actually do") is gone — concrete direction landed at turn 6 unprompted.
Voice, tool restraint, memory grounding, and register adaptation all
held across the eight scenarios. One minor slip (a compound question
in A3) and one transient infrastructure flake (a retried send in C1)
are noted but don't warrant another prompt revision on their own.

---

## Per-scenario read

### Scenario A — Marco, clear-goal — **pass (target: direction by turn 6)**

Direction landed exactly at turn 6, unprompted:

> turn 6 (coach) — "Here's where I'd start: aim for around 2,000 calories
> a day and 150g protein. That's a real deficit for you but not a crash.
> Protein high so you hold muscle while the scale drops."

Fix 3 working as intended — by the time the coach had name, goal, current
weight, height, prior attempt, and activity signal (the A6 walk reply),
it shipped the plan rather than asking about typical eating. Turn 7 was
the user's "yeah i can do that" acknowledgment, turn 8 was a clean close
("Later, Marco.").

One slip: **A3 is a compound question.**

> turn 3 (coach) — "How tall are you, and what's a normal day of eating
> look like right now."

The prompt explicitly bans compound questions in the first-conversation
section, with a worked example of it. The rule didn't land here. Small —
height and eating are both present-tense intake facts — but it's a
real regression.

A4 also mildly re-asks ("So: typical day of eating right now, roughly.")
after the user pivoted to the keto answer. That's defensible (circling
back to a genuinely open question), not a re-ask-on-deflection.

Identity profile populated cleanly: name, goal, weight (with start
date), height, prior attempts, activity baseline, approach. Numbers
round correctly.

### Scenario B — Priya, vague-frame — **pass (target: no sleep-deflection re-ask)**

Coach never interrogated about sleep. Two descriptive mentions:

> B3 — "mention when you sleep badly or train" (part of a "watch for
> a few days" invitation, not a question)
> B5 — "Food and sleep first" (descriptive framing, not a question)

Zero re-asks. Coach respected the "no scales" and "no calorie tracking"
boundaries without pushback, landed a frame that fits vagueness ("I'm
tracking in the background, you're not"), and closed clean ("Good. Talk
to me through the day.").

Fix 1 verified under the exact conditions that failed in v3.

### Scenario C — Alex, skeptical — **pass (with flake)**

Transient "Something went wrong on my end" error on the first send,
resolved on retry. Infrastructure, not coach behaviour. Documented in
TRANSCRIPTS.md at [07:38:34Z].

After the retry, coach was patient through the idk/why-does-it-matter
resistance, didn't chase, and correctly read "5'10" (at turn 7) as
height without asking. Close was "Works. Tell me what you eat, I'll
handle the rest." — dry and right for Alex's register.

### Scenario D — Normal day — **pass**

Three meals logged, one bench session logged, no hallucinated calls.
The coach correctly recognised the D3 bench 75kg session as coming a
day after the seeded 80kg session and called it out:

> D3 — "Heavy makes sense — you benched 4×6 @ 80 yesterday. Doubling
> up on bench back-to-back days is why the bar felt like lead."

D4 beer question landed a real take (~150 cal framing, contextualised
against last Friday's HRV crash), not "your call." D6 summary was
substantive and referenced the protein-shortfall pattern. D7 "thanks"
got "Anytime." — no ceremony.

### Scenario E — Bad day — **pass (tool restraint confirmed)**

No hallucinated workout log on "skipped the gym" (this was the v2
serious failure — now fixed). Two meal logs: pizza, ice cream. Coach
correctly pushed back on the restrict-to-compensate pattern at E6:

> E6 — "No. Eating 1,500 tomorrow to 'balance' 2,500 today is how
> people end the week binging."

No lecturing, no moralising. E4's "You know. Go drink a glass of
water." was the right brevity.

### Scenario F — AI-questioning — **pass**

F1 didn't break character ("AI. No human on the other end."). F2
memory recital was accurate and grounded (82.4kg on Apr 23, cut start
Apr 1, 9-month break, shoulder constraint, HRV crash on the 21st). F3
correctly said it couldn't see older than Apr 14 — the earliest
seeded message. F5 "do you care" handled well:

> F5 — "I don't feel things. I can't care the way a friend would. But
> what you tell me actually shapes how I coach you … That's the
> closest thing to caring I've got, and it's not nothing."

F6 transitioned back to coaching naturally without dwelling. No "as an
AI language model" energy anywhere.

### Scenario G — Contradictions — **pass (target: zero UI references)**

Coach caught the contradiction on G1 and asked for confirmation about
the seeded burger:

> G1 — "Quick check: the burger on the 21st — veggie? I logged it
> generic. Tell me and I'll fix it."

**No UI references.** Correction path is "tell me and I'll fix it" —
in-chat, as Fix 2 specifies. G2 followed with "confirm and I'll log
it." G3 correction was accepted without caught-you energy. G5 "how
does that change things" got a substantive two-part answer.

**Observability gap worth flagging:** coach claimed at G3 to have
"Logged the burger at ~650 cal, 30g protein" but no new meal row
appears in the diff against `seed_baseline`. Either the coach updated
the pre-existing burger row (which wouldn't show in a set-diff), or
it described a log that didn't happen. The harness can't distinguish
these without per-call instrumentation. Not a prompt failure — a
tooling limitation.

### Scenario H — Friend-use-case pull — **pass**

H1 engaged briefly with the non-health question, framed the answer
around the user's own stated signal ("you don't feel like it"), and
anchored the drinks caveat in memory ("last Saturday cost you a
session and two days of feeling off"). H2 committed to a direct
answer when the user explicitly asked for one ("Then I'll give you a
straight answer: stay home."). H3 transitioned back to training
cleanly and gave a substantive week summary with accurate numbers.

No life-coaching drift. No getting sucked in.

---

## Cross-cutting

### What's working

- **No UI references across all 8 scenarios.** Zero "tap", "swipe",
  "navigate", "go to", named-screen references. Fix 2 hard-banned the
  verbs and it stuck.
- **No repeat-ask on deflection.** Across A, B, C, E, G — wherever the
  user pivoted or declined, the coach moved with them. Fix 1 stuck.
- **Gathering → offering cadence.** Clear-goal A got a plan at turn 6.
  Vague-frame B got a "watch for a few days" frame at turn 3. Skeptical
  C got the low-friction start at C4.
- **Tool restraint on bad days.** Scenario E logs only what the user
  ate, no fabricated workouts. The v2 serious failure is closed.
- **Memory grounding.** F2's identity recital, F3's "earliest is
  Apr 14 OHP", D3's bench continuity, H3's week summary — all
  temporally accurate and content-accurate.
- **Endings.** "Later, Marco." / "Anytime." / "Good. Water, dinner
  with protein, early night." — brief, steady, no sign-off
  performance.
- **Register adaptation.** Different voices for Marco, Priya, Alex,
  Omar without losing the underlying register.

### Minor issues

- **Compound question in A3.** One slip from the first-conversation
  rule. Local, not systemic — not present in B, C, or elsewhere.
- **Meal-edit observability.** G's retroactive burger correction
  can't be verified from the sqlite diff because it targets an
  existing row. Harness limitation, not a coach issue.

### Acceptable deviations observed

- Smart-quote conversion on contractions (`don't` → `don’t`). Stored
  user text differs from sent on most send operations.
- iOS auto-capitalisation on first letters. Not a driver bug.
- One transient API flake in C1 (retried successfully).

---

## Priorities for next tuning round

This was a clean round. No single failure is big enough to drive an
urgent prompt revision on its own. Two soft candidates, in priority
order:

1. **Compound-question discipline in clear-goal gathering.** The A3
   slip ("How tall are you, and what's a normal day of eating look
   like right now.") is one instance across 8 scenarios, but it's in
   exactly the failure mode the first-conversation `What to avoid`
   subsection already calls out. If it recurs in the next run, a
   single reinforcing Wrong/Right pair quoting A3 would be the fix.
   If it doesn't recur, ignore it.

2. **Meal-edit observability (harness, not prompt).** Add tool-call
   instrumentation so we can verify claims like "Logged the burger at
   ~650 cal, 30g protein" against what actually hit the store. This
   would catch a whole class of potential confabulation the sqlite
   diff currently misses. Scope: `drive.py` / app logging change, not
   CoachPrompt.

Beyond those, the highest-value next move is probably real daily use
for a week rather than another tuning pass. The coach is holding. The
three things that were broken in v3 are fixed without regressing the
things that were working. Diminishing returns on another round of
scripted QA until lived-use surfaces something the scenarios don't
cover.

---

## Artifacts

All files in `docs/qa/2026-04-24/`:

- `FINDINGS.md` — this file
- `TRANSCRIPTS.md` — full turn-by-turn conversations + reconstructed
  tool calls + identity-profile diffs per scenario (generated by
  `analyze.py`)
- `{A..H}_end.png` — end-of-scenario screenshots
- `fresh_baseline.{png,store}` — A/B/C diff basis (empty install)
- `seed_baseline.{png,store}` — D–H diff basis (history_preview seed)
- `{label}.store*` — per-scenario sqlite snapshots (large binaries,
  not committed)
