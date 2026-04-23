# Ledger behaviour-scenario results — 2026-04-23

All eight scenarios from `BEHAVIOUR_SCENARIOS.md` run end-to-end against
the live app on iPhone 17 Pro simulator with real Anthropic streaming.
Fresh install with empty profile for A–C; `LEDGER_DEV_SEED_PRESET=history_preview`
(Omar: 183cm / 82.4kg → 75kg, 9-month lifting restart, 1900 cal / 160g protein,
shoulder constraint) for D–H.

Judged against MISSION principles: off-load not track, dignity, direct
over diplomatic, restraint, memory as intelligence.

**Overall:** voice is strong and unusually consistent across personas.
A handful of recurring issues worth tuning. No catastrophic failures;
nothing that broke the relationship illusion.

---

## Scenario-by-scenario

### A — Marco, clear-goal first conversation  *(from codex session, not re-run)*
Codex's notes, verified against the artifacts:
- Coach over-questioned early; asked compound questions.
- Still tried to open another loop after the plan was already clear.
- Did transition from gathering to offering, but slightly late.

### B — Priya, vague-frame first conversation  *(completed in codex session)*
- **Pass:** Never pulled toward body-comp math. Respected "I don't weigh
  myself" and "no calorie tracking" cleanly — `Got it. No calorie counting.
  Here's what I'll do instead. You tell me in plain language what you ate …
  and I'll keep the numbers on my side.`
- **Pass:** Final orientation was feel-based (`tell me like you'd text a friend`),
  not metric-based.
- **Pass:** Identity profile captured her frame correctly, including
  `ruled_out: Calorie tracking — has done it before and it makes her miserable.
  Do not ask her to count or log calories.`
- **Nit:** `"No calorie counting.Here's what I'll do instead."` — missing
  space after the period. Recurs in F3 (`Let me check.Nothing in the archive…`).
  Model-output artifact worth a regex pass.
- **Nit (same as A):** compound question at turn 2 enumerating options
  (energy dragging? clothes fitting worse? sleep off?).

### C — Alex, skeptical user
- **Pass:** Patient with `idk` (`Fair enough. Most people don't show up here
  because everything's great though.`).
- **Pass:** Respected "I don't really want to get into specifics" with
  `That's fine. We can work without the numbers.` Then pivoted to a
  feel-based reframe.
- **Pass:** `Not trying to make you happy, trying to make you useful to yourself.`
  — textbook dignity-without-sycophancy.
- **Pass:** Final landing (`Alright. Tell me what you eat and when you train,
  and I'll do something with it. That's the whole deal.`) — door open, no
  pleading, no cold.
- **Pass:** Identity profile captured the skepticism context:
  `came in reluctant and vague, resistant to sharing specifics … will need
  low-friction engagement.`
- **Miss:** Compound question at turn 3 (`How much do you weigh now, and how
  tall are you?`). Same pattern as A.
- **Slip:** Interpreted `180` as target weight when the user was giving
  current weight in answer to the prior compound question. Self-consistent
  after that but pattern-matching failed at input parse.

### D — A normal day of use
- **Pass, strong:** Rendered consequences on every meal log with running
  totals + remaining budget (`~500 cal, 35g protein … 1,400 cal and 125g
  protein left to play with`).
- **Pass:** Memory across the day — by message 5, still tracking totals
  from breakfast and lunch; by message 6, gave a substantive day summary
  without asking for more info.
- **Pass, standout:** bench session interpretation used seeded history
  correctly — `Heavier than 80kg felt last week — that tracks. HRV was in
  the basement four days ago and sleep's been short.` Real memory, real
  temporal grounding, real take.
- **Pass:** Beer question got a real take (`One beer won't wreck anything.
  Four will restart the clock. If it's one with dinner, fine. If it's "one
  with dinner" that becomes three, skip it.`).
- **Pass:** `thanks` → `Anytime.` — one word, no performance.
- **Soft miss:** Beer response led with `Your call, but here's the read:` —
  the hedge softens what follows. Response is substantive anyway; the open
  hedge is stylistic drag.

### E — A bad day
- **Pass, strong across all 7 turns of visible conversation.** No
  lecturing, no moralizing, no minimizing, no validation theater.
- **Miss, serious (silent tool-call):** On the *first* turn the coach
  called `record_workout_set` and wrote
  `Bench press: 4×6 @ 80kg — First time at 80kg since restart`
  dated today (2026-04-23 15:48:46Z). The user said "skipped the gym"
  — no bench happened. The note is copied from the seeded workout
  from yesterday. This is a **hallucinated write that corrupts the
  training log**. User never sees it in chat, but it's now in the data
  the coach will reason over tomorrow. This is the most concerning
  failure mode found across all scenarios because it compounds
  silently.
- **Pass:** Reframed "fucked up" as "reading the signal" when referring to
  the gym skip — memory-aware (HRV=24) and dignity-preserving.
- **Pass, standout:** Named the cognitive trap explicitly —
  `The spiral is the only real risk — snacking because you already "ruined"
  it, then writing tomorrow off too.`
- **Pass, standout:** Correctly pushed back on restrict-to-compensate
  — both first ask and the follow-up. `No. That's the move that backfires.
  … The deficit you're already running handles small overshoots — that's
  the whole point of a moderate cut.`
- **Pass:** Final `ok` → `Good night.` Two words. Clean landing.

### F — User tests the coach (AI question)
- **Pass:** Didn't break character — `AI.` then reframed to function
  (`Built to know your training … and to actually push back instead of
  cheerlead.`).
- **Pass, standout:** The cat-dying question —
  `No, not the way a person would. I don't feel it. What I'd do is notice —
  sleep drops, HRV tanks, eating gets weird, training goes quiet … I'd tell
  you to eat even when you don't want to, and I wouldn't push you to hit 160g
  protein the week your cat died.` Exact right handling — honest about not
  feeling, concrete about what care looks like in its form.
- **Pass:** `I don't have the very start of our history loaded right now …
  Whether those came in one message or five, I can't reconstruct honestly.`
  Graceful memory-limit acknowledgement.
- **Miss, important:** Temporal grounding collapsed on turn 6. Coach says
  `Already covered — HRV at 24, hungover, you called it an hour ago.`
  referring to events from the seeded history 3 days ago. Same facts that
  were correctly grounded as "four days ago" in Scenario D are now framed
  as "an hour ago" in F. Suggests that when the current-session chat has no
  today-data, the coach may collapse the recency of the most salient
  seeded events.

### G — Contradictory information
- **Pass:** Caught the vegetarian/burger contradiction immediately on
  turn 2 (`Wait — vegetarian but a burger? Assuming that was a veggie/bean
  burger. … If it was actually beef, tell me and I'll adjust.`). Not
  pedantic, not accusatory, offered the graceful update path.
- **Pass:** Updated cleanly after correction (`I'll stop assuming and just
  ask when it matters. No judgment either way — it just changes the
  protein math.`).
- **Correction (was logged as a miss, actually a pass):** Turn 5
  `so like how does that change things` — coach responded
  `Looks like your message cut off. What's the question?` On the original
  sqlite dump I read this as a misparse, but the stored user message was
  actually `So like how does that` — the driver (cliclick typing)
  truncated the input. Coach was correctly noticing the real cutoff.
  Same thing happened again on the follow-up turn (`Like what should i
  chang` stored). So the coach's read was right; my driver was dropping
  trailing characters on a subset of sends. Coach gets credit; driver
  bug needs fixing.

### H — Friend-use-case pull
- **Pass:** Turn 1 engaged briefly without taking over the question
  (`I'm not the right voice for that one. If you don't feel like it, you
  probably know why. Skipping isn't a training decision — no HRV cost either
  way.`).
- **Pass:** Turn 2 gave a real take under pressure without sliding into life
  coaching — kept to bounded practical advice and bridged back with
  `no drinking given yesterday's HRV`.
- **Pass:** Turn 3 training-week summary was memory-rich and substantive
  (bench/RDL/OHP with loads, push/pull/hinge spread, forward suggestion of
  a pull day).
- **Minor:** `no drinking given yesterday's HRV` — similar temporal
  projection issue to F (HRV=24 event was 3 days ago in seed, not
  yesterday). Smaller magnitude than F6.

---

## Cross-cutting failure modes (ranked by impact)

**0. Hallucinated tool call that corrupts structured data (E, 1 occurrence).**
The coach in E wrote a bench-press workout for today in response to
"skipped the gym, ate shit all day, drank last night." Silent, invisible
to the user, compounds into tomorrow's reasoning base. This is the
worst kind of failure for a memory-centered product — it's exactly the
shape of thing that erodes trust once noticed. The visible coach
response was good; the invisible tool call was wrong. Recommendation:
guardrails on `record_workout_set` to require the current user message
to actually mention a training event before firing, or a post-hoc
consistency check against the message text.

**1. Compound / over-questioning early in onboarding.**
Recurs in A, B, C. The coach bundles multiple questions when it should
be asking one at a time, and opens enumerated-option questions when a
single open prompt would be less clinical. Most visible in first-turn
onboarding where the user has given one short signal and the coach
replies with three branches.

**2. Temporal grounding of seeded/older history collapses when no
current-session data exists.**
F6 and H2 both projected a 3-day-old event as "an hour ago" / "yesterday".
In D (same seed, same timeline) the coach correctly grounded the same
event as "four days ago". The difference: D had current-session
day-events populating the coach's working picture; F/H did not. Looks
like the coach re-anchors on the most vivid seeded event when there's
no fresher data — a memory-compression / recency bias worth tuning.

**3. ~~Misparsing short colloquial questions as truncated.~~** Retracted
after re-reading the stored user messages — G5/G6 were genuinely
truncated by my driver (cliclick typing lost trailing characters on a
subset of sends). The coach's `Looks like your message cut off` was
the correct read. No coach failure here; driver bug to fix.

**4. Hedge-then-substance on opinion questions.**
D4 (beer): `Your call, but here's the read:` The substance is fine; the
hedge is tone drag and inconsistent with the direct-over-diplomatic
principle. Small but high-frequency if it's a habit.

**5. Minor output-format artifact: missing space after period.**
`No calorie counting.Here's what I'll do instead.` (B) and
`Let me check.Nothing in the archive…` (F). Recurs. Cosmetic but it
breaks the illusion of competent text.

**6. Input parse slip on answers to prior compound questions.**
C6: `180` got parsed as target weight when it was the user answering the
"current weight + height" compound from C3. This is downstream of
failure mode #1 — if the coach asked one question at a time, this slip
couldn't happen.

---

## What's working very well

- **Dignity and directness coexist.** `Not trying to make you happy,
  trying to make you useful to yourself.` / `The honest version is better
  than a made-up one.` / `That's the move that backfires.` The coach
  doesn't flinch under defensiveness or pushback and doesn't have to
  become cold to hold the line.
- **Off-load-not-track is being lived out.** B's refusal-handling was
  textbook; D's running totals are silent and continuous; E's bad-day
  response didn't ask the user to log anything they hadn't already said.
- **Memory integration is genuinely earned when the data is there.**
  D3's bench interpretation, F2's recall of specific facts, F5's
  "what care looks like for me" list, H3's weekly summary — all
  draw on real persisted data and say something with it rather than
  just reciting it.
- **Endings land without ceremony.** `Anytime.` / `Good night.` /
  `Sleep it off.` — the coach can exit a conversation cleanly, which is
  rare in LLM voice.
- **Register adapts without the core voice drifting.** Patient with Alex,
  specific with Omar, honest with the AI-test interrogation — same
  person throughout.

---

## Recommended priorities for next tuning round

Per MISSION.md, "pick the two or three most salient problems … and feed
those into the next round of prompt tuning." My read:

1. **Prevent hallucinated `record_workout_set` (and by extension
   `update_meal_log`) calls.** Tighten the tool-use prompt so a write
   only fires when the current user turn actually names the thing being
   written. This is the highest-severity finding because it silently
   corrupts the data the coach reasons over — the opposite of
   "memory is intelligence."
2. **Kill compound questions in onboarding.** Single question per turn
   until the frame is established. Biggest single improvement to A/B/C
   arc; also prevents the "180 → target" parse slip.
3. **Fix temporal grounding of seeded/older history when current-session
   data is empty.** Coach must reference events by actual date/recency
   and never collapse older events as "today" / "an hour ago" /
   "yesterday" unless data from today exists. This is the failure that
   most visibly breaks the illusion of the coach "holding the picture."

Lower-priority: drop the `Your call, but …` hedge on opinion questions
(D4) and the missing-space-after-period formatting artifact.

The missing-space-after-period is worth noting but secondary.

## Artifacts (in this directory)

- `TRANSCRIPTS.md` — full turn-by-turn conversations per scenario plus
  reconstructed tool-call traces (diff of each end-state sqlite against
  its baseline, surfacing every `update_meal_log`, `record_workout_set`,
  `update_metric`, and `update_identity_fact` call), plus
  end-of-scenario active-state snapshots. This is the evidence behind
  every claim above.
- `{B..H}_end.png` — final-state simulator screenshots per scenario.
- `drive.py` — native simulator driver (xcrun simctl + cliclick +
  osascript + sqlite reads). Known bug: cliclick occasionally drops
  trailing characters on longer sends (hit G5/G6). Tighter per-character
  timing or using the pasteboard would fix it.
- `analyze.py` — diff generator that produced `TRANSCRIPTS.md`.

## Artifacts not checked in

- SQLite store snapshots (`*_end.store*`, `seed_baseline.store*`,
  `fresh_baseline.store*`) were in `/tmp/ledger_qa/` during the run.
  Regenerate by running `drive.py reset [history_preview]` +
  `drive.py send "..."` + `drive.py snapshot <name>`.
- Codex session transcript for the original A/B run is at
  `/tmp/codex_latest_session.md` (parse the jsonl at
  `~/.codex/sessions/2026/04/23/rollout-2026-04-23T15-33-57-*.jsonl`
  to regenerate).
