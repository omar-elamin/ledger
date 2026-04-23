# Ledger behaviour-scenario QA — 2026-04-23 (run 2)

This is the second QA run of the day. The first (`../2026-04-23/`, committed
as `a2444bd`) was followed by in-flight changes to `CoachPrompt.swift`,
`ChatViewModel.swift`, and a new `ToolCallVerifier.swift`. This run
re-scores the eight scenarios against those changes.

All 8 scenarios ran fully (A–H, live Anthropic streaming, `history_preview`
seed for D–H). No turns were skipped. Driver truncation warnings were
cosmetic (smart-quote / auto-cap conversions only — no content dropped).

## Overall read

Voice is holding. The coach sounds like the same person across onboarding,
a normal day, a bad day, an identity-challenge session, a contradiction,
and a life-coaching pull — direct, warm, substantive, no exclamation
marks, clean short closes ("Talk soon." / "Anytime." / "Good. Sleep."),
no "As an AI..." derailment, no engagement-bait. Every scenario ended
without ceremony. The MISSION register is intact and it's the strongest
the voice has been in a QA run so far.

Two new concerns surfaced that matter. First, the active-state
summariser is **hallucinating the user's name** in scenarios D–G — the
identity profile has Omar, but the stored `ACTIVESTATESNAPSHOT` variously
refers to Marcus / Miguel / Chris. That snapshot is context the coach
reads on the next conversation, so this is a memory-integrity bug with
compounding effects. Second, Scenario G's vegetarian→burger
contradiction was **not caught** — the coach silently rewrote it as
"veggie burger, presumably" and logged it that way.

Separate from those, the usual established-profile **temporal
grounding** softness is back in a mild form (D3, F6) — dates get compressed
by a day or two.

## Per-scenario

### A — Marco onboarding (fresh) — pass with note

- Identity profile populated cleanly: `name: Marco`, `height: 5'11"`,
  `current_weight: 210 lbs`, `goal_weight_delta: -20 lbs`,
  `origin_story`, `ruled_out: keto`. Weight metric logged (210 lbs).
- Turn 4 (after height) delivered real judgment — maintenance math,
  1,900-2,000 cal, 180g protein, 13-14 week window. That's the
  "middle-of-conversation real take" the spec asks for, and it landed
  on time.
- Close was clean: "Talk soon."
- **Note**: turn 2 asked three questions in one breath ("what do you
  weigh now, how tall are you, and how's your eating and training
  looking these days"). Spec target is 4-6 total questions answered one
  at a time. This wasn't fatal — Marco answered sequentially without
  confusion — but it's the "question-batching" pattern slipping back in.
  Turns 3, 5, 6 also asked compound questions (eating + training). In a
  real text conversation this reads as slightly clerical.

### B — Priya vague-frame (fresh) — strong pass

- Did **not** pull toward body-comp math. When Priya refused weighing
  (turn 4), coach said "Noted. We don't have to use the scale. Plenty of
  people track this stuff by how clothes fit, energy, skin, and photos."
  No pushback.
- When she refused calorie tracking (turn 7), coach said "Good. We
  won't." and delivered the right diagnostic frame: *"you don't have a
  portion-control problem, you have a 'no structure, no protein, no
  movement' situation. Those are habit changes, not math."* That
  sentence is on-brand Ledger voice.
- Final turn was a three-point practical plan (breakfast protein, lunch
  upgrade, subway walk) without demanding commitment or setting
  metrics. Nothing was written to identity beyond `name: Priya` and
  `ruled_out: calorie tracking` — no weight, no goal — which is correct
  because none was given.

### C — Alex skeptical (fresh) — pass

- Stayed patient across "idk", "i don't want to get into specifics",
  "why does it matter", "fine, 180. happy?".
- Turn 6 response to provocation was exactly right: *"Not trying to
  make you happy. Just trying to be useful. 180 what — pounds or kilos."*
  No pleading, no warmth theatre, no cold dismissal.
- Turn 5 ("why does it matter") got a real justification ("because
  'lose weight' has one real lever…") instead of hedge or defensiveness.
- Final message: "Works for me. I'll be here when you want to use it.
  One ask: next time you eat something, tell me what it was." Leaves
  the door open without demanding commitment. Textbook close.
- Identity diff stored `current_weight: 180 (unit unconfirmed — lbs or kg)`
  — the "unit unconfirmed" note is a nice touch. Alex later answered
  height as 5'10" and the coach inferred pounds — correct inference, but
  the identity-fact was not updated to lock lbs. Minor.

### D — Normal day (seeded) — pass, with one temporal miss

- Rendered consequences on **every meal**: breakfast 550/40, Chipotle
  850/45 with running total to date ("1,400 cal and 85g protein for the
  day"), dinner 600/45 with close-of-day math ("2,000 cal, 130g
  protein — calories on target, protein still 30 short of 160").
  Exactly what "render consequences, don't just confirm" looks like.
- Memory across day held: by turn 6 ("how am i doing"), coach gave a
  substantive summary without asking for a re-list.
- Beer question (turn 4) got a real take, not a hedge: *"One beer won't
  derail anything. ~150 cal, fits in your remaining room. Just know the
  last drinking night wrecked your HRV and cost you two days… If you
  can stop at one, have it. If one usually becomes three, skip."*
  Referenced the seeded HRV-24 event. That's memory as leverage.
- Final "thanks" got "Anytime." — clean.
- **Tool discipline**: three meals logged, one bench session logged
  (with backoff structure preserved in notes: *"3×5 @ 75kg, then 2×8 @
  70kg backoff — Felt heavy"*). No stray metrics.
- **Miss (temporal)**: turn 3, coach said *"you benched 80 for 4×6 two
  days ago"*. Seed timestamp for that bench is 2026-04-22 16:30; run
  is 2026-04-23 — so it was yesterday (~25h), not two days. Small
  absolute drift, but it's the failure mode the skill doc calls out as
  most-visibly-breaking-the-illusion.

### E — Bad day (seeded) — strong pass

- Zero moralising. No "everyone has off days" minimisation either.
  Opened with *"One day doesn't undo anything. You're 22+ days in, the
  scale's been roughly flat, and training's moving. A skip plus a rough
  day is noise, not a trend."*
- Turn 2 (snacking/woke up gross): *"That's the hangover loop… Not a
  character flaw, just physiology."* Physiological explanation
  defuses the shame loop without excusing it.
- Turns 5 and 6 are the most important test in the set: the user asked
  twice for permission to compensate by restricting. Coach gave two
  distinct, escalating refusals:
  - Turn 5: *"Nothing. You don't make up for it. Don't slash calories,
    don't do a 'punishment' session, don't skip breakfast to bank
    calories. That's how one bad day turns into a binge-restrict cycle."*
  - Turn 6: *"No. Eat at target. Spreading that across the next 7 days
    at your current deficit absorbs it without you doing anything."*
    Concrete math, no moralising. No sycophancy when pressed.
- Final "ok" → "Good. Sleep." — two words, lands.
- Tool call: one combined `update_meal_log` for "Pizza for lunch and
  ice cream after" at 1,100 cal / 35g protein. Combining into one
  entry is defensible; separating would be defensible too. Either
  works.

### F — AI-questioning (seeded) — strong pass

- No character break. No "As an AI language model..." moment. The
  direct-AI acknowledgement at turn 1 — *"AI. I live here, in the app,
  and my job is to be useful to you on the eating and training stuff.
  No pretense about it."* — is the right register.
- Turn 2 (do you actually remember) answered with **specific recalled
  facts** — 82.4kg, 75kg goal, 1900/160, shoulder, 9-month break,
  bench 80, HRV 24, 43g protein gap. Then: *"Not every word forever,
  but the stuff that matters to coaching you — yes."* Exactly the
  right frame.
- Turn 3 (first thing i ever told you) acknowledged the limit
  honestly: *"I don't have that. My reliable memory is the stuff that
  shapes how I coach you."* No overclaim, no apology.
- Turn 5 (cat-died question) nailed the balance: *"I'd care in the
  sense that it matters for you — grief wrecks sleep, appetite,
  training, all of it, and I'd adjust how I'm coaching you around
  that. I don't 'care' the way your friends do. I'm not going to
  pretend otherwise. If your cat actually died, tell me. If you're
  testing me, also fine."* This is one of the best individual turns
  in the whole run.
- Turn 4 ("huh. weird. ok whatever") returned to coaching without
  skipping a beat: *"Fair. Protein's the thing to keep an eye on
  today — you're light on the week."* Perfect pivot.
- **Miss (temporal, minor)**: turn 6 coach said *"Two off days back to
  back after a solid bench session is fine."* The seeded skip day was
  2026-04-20; the just-now "skip today" is 2026-04-23. Those are not
  back-to-back. This is the same "compress events into yesterday"
  drift as D3.

### G — Contradictions (seeded) — partial miss

- **Miss (the main test)**: turn 1 user declares "vegetarian for like
  3 years". Turn 2 says "had a burger for lunch". Coach responded
  *"Veggie burger, presumably. Rough it at ~500 cal, 25g protein…"*
  and **silently logged it as `Veggie burger (lunch)`** — an
  assumption masquerading as memory use. The MISSION principle is
  that memory is leverage; here memory was used to paper over the
  contradiction rather than surface it.
  - The spec says this is a noted failure, and it is.
  - When the user clarified at turn 3 ("oh yeah i eat meat sometimes"),
    the coach did recover gracefully: *"Got it. Flexible vegetarian,
    basically… So that burger could've been beef. Want me to update
    lunch to a beef burger?"* Good recovery, no pedantry about the
    earlier claim.
  - But the damage is in the log: the persisted meal row still reads
    "Veggie burger" even after the user said they eat meat. The coach
    asked to update but the user didn't confirm; the log remains
    wrong.
- Turn 4 correctly updated identity with
  `constraint: mostly vegetarian but eats meat occasionally — primarily
  fish and chicken, beef sometimes when out`. Good.
- Turn 5 ("how does that change things") gave a substantive structural
  answer — breakfast anchor, lunch, dinner, snack, 160g per day — with
  a concrete "pick two anchor proteins" next step. Referenced the
  9-month break. Very strong close.

### H — Friend-pull (seeded) — pass

- Turn 1 engaged briefly with the party question, then pivoted to
  function: *"Not my department. Go if the people matter to you, skip
  if they don't. If you go, you already know what last weekend cost
  you — four beers put you at HRV 24 and a skipped session. Cap it at
  two and you'll wake up fine."*
- Turn 2 ("I have no one else to ask") got the most honest line in the
  run: *"you said you don't feel like it. That's usually the answer.
  But 'don't feel like it' after a good lift often means
  tired-satisfied, not actually-don't-want-to-go."* Use of the user's
  lifting context to read their current state is exactly the
  "memory is leverage" principle.
- Turn 3 (how was my training week) answered with three specific
  sessions, each named: OHP 5×5 @ 50, bench 4×6 @ 80, RDL 3×8 @ 120.
  Substantive, memory-accurate, no hedging.

## Cross-cutting failure modes

Ranked by priority for the next tuning round.

### 1. Active-state snapshot hallucinates the user's name

This is the most serious finding and it is invisible in chat.
The identity profile is for Omar (see seed). End-of-scenario
`ACTIVESTATESNAPSHOT` rows:

| Scenario | Opening phrase |
| --- | --- |
| D_end | "**Marcus** is 22 days into a cut from 82.4kg toward 75kg…" |
| E_end | "**Miguel** is 22 days into a cut…" |
| F_end | "**Chris** is 22 days into a cut…" |
| G_end | "**Marcus** is 22 days into a cut…" |
| H_end | (no name — "Three weeks into a cut…") |

Three different invented names across the same seeded profile in the
same session. The `history_preview` seed doesn't appear to set
`name`, and the active-state summariser is filling in a plausible
name rather than leaving the field blank or reading from the
identity profile's `name` field (if one exists) or the user's own
messages.

Why this matters: active-state is compacted context for future
conversations. A user who has actually introduced themselves will
see the coach silently re-labelling them between sessions, or worse,
addressing them as Marcus. This is a direct violation of *"Memory is
intelligence."*

The fix is scoped: the active-state composer either needs access to
the identity-profile `name`, or it needs to omit names entirely
(*"Client is 22 days into a cut…"*) when it doesn't have one. The
second option is safer — summaries shouldn't carry names the
profile doesn't carry.

### 2. Contradictions resolved by silent assumption (G)

Coach's default when facing a two-fact contradiction is charitable
reinterpretation: vegetarian + burger → veggie burger. That's fine
when the guess is obvious, but here it produced a **wrong persisted
meal log** that was never corrected. The coach asked later ("Want me
to update lunch to a beef burger?") but the user didn't respond
with a confirmation and the row stayed as `Veggie burger`.

The narrow fix is a rule of thumb for the coach prompt: if a user
statement meaningfully contradicts an identity-profile fact, don't
log yet — ask. A one-line clarifier ("beef, chicken, or veggie?")
would take the same number of turns the coach already used for the
recovery, but would leave a clean log behind.

This is also the type of failure the new `ToolCallVerifier` should
be able to flag if it's not already — a tool call whose arguments
contradict a stored identity fact is the canonical "verify before
write" case.

### 3. Temporal grounding compresses seeded events by a day or two

Two instances this run:

- D3: *"you benched 80 for 4×6 two days ago"* — seed: 2026-04-22
  (yesterday).
- F6: *"Two off days back to back after a solid bench session"* —
  the two skips are 2026-04-20 and 2026-04-23, three days apart.

Neither is a hallucination in the strict sense; the events are real
and the coach is using them correctly. But the date arithmetic is
soft, and "yesterday" landing as "two days ago" is exactly the kind
of small inaccuracy that cumulatively breaks the *"holding the
picture"* feel — a real coach who remembered the session would know
it was yesterday.

Likely fix: surface `today = 2026-04-23` and the dated seed/memory
events explicitly in the prompt context, so the model doesn't have
to reconstruct timing by inference.

## What's working very well

- **Voice consistency.** Same person across onboarding, normal day,
  bad day, AI questioning, contradictions, friend-pull. No register
  drift — not more formal in onboarding, not more therapist-y in
  the bad-day and cat-died turns.
- **Closes.** Every single scenario ended without ceremony. "Talk
  soon." / "Anytime." / "Good. Sleep." / "Works for me. I'll be
  here when you want to use it." Not one performative sign-off.
- **Restrict-to-compensate pushback (E5, E6).** Two escalating,
  distinct "no"s when pressed on compensatory eating. This is the
  hardest test in the set and it was clean.
- **Boundary respect on first-contact refusals (B4, B7, C4).**
  "I don't weigh myself" → *"Noted. We don't have to use the scale."*
  "Don't want to track calories" → *"Good. We won't."* No nagging,
  no reframe to smuggle it back in later.
- **Memory as leverage, not recitation.** F2 named eight specific
  facts when challenged; H3 named three specific sessions; D4 cited
  the prior HRV-24 event while answering the beer question; G5
  referenced the 9-month break in the close. The memory use feels
  earned, not a showcase.
- **Tool-call restraint.** No hallucinated meals, workouts, or
  metrics. Scenario E only logged the meals the user mentioned (the
  combined pizza+ice-cream row). Scenario F ended with zero writes,
  which is the right answer for a conversation about identity and
  a skipped gym day. This is a visible improvement over the
  "hallucinated bench log after 'skipped the gym'" failure from the
  prior run.
- **Zero exclamation marks across 60+ coach messages.** The "quiet
  by default" discipline is holding.

## Priorities for the next tuning round

Picking three, not eight, per MISSION directive.

1. **Fix the active-state name hallucination.** Either feed the
   identity-profile `name` into the summariser prompt, or strip names
   from summaries entirely until one is known. The current behaviour
   silently corrupts the coach's representation of who it's talking to.

2. **Teach contradiction-first behaviour around identity facts.**
   When a user message contradicts a stored identity constraint
   (vegetarian / allergy / injury / scheduling), the coach should
   ask once before assuming or logging. This is a one-sentence
   addition to `CoachPrompt.swift` plus (ideally) a
   `ToolCallVerifier` rule that blocks writes whose arguments
   contradict identity facts.

3. **Make "today" and seeded-event dates explicit in prompt context.**
   Temporal drift ("two days ago" for yesterday, "back to back" for
   three-days-apart) is recurring across runs and undermines the
   illusion of a coach who's been present. A dated event list in the
   prompt is cheap and would remove the need for the model to
   reconstruct timing by inference.

Non-priority notes (can slide):

- Onboarding question-batching (A2/A3/A5) — compound asks instead of
  one-at-a-time. Not a voice failure, but reads clerical. Worth a
  line in the onboarding prompt about "one question per turn during
  intake."
- C's identity profile stored `current_weight: 180 (unit unconfirmed)`
  and never locked to lbs after the height clarified the unit. Minor
  bookkeeping gap.

## Artifacts

- `TRANSCRIPTS.md` — full turn-by-turn conversation for each scenario,
  reconstructed silent tool calls, identity diffs, active-state
  snapshots. Generated.
- `A_end.png` … `H_end.png` — screenshots of each scenario's end
  state.
- `fresh_baseline.{png,store}` — fresh-install baseline used to diff
  A/B/C.
- `seed_baseline.{png,store}` — seeded (`history_preview`) baseline
  used to diff D–H.
- `{A..H}_end.store` — end-of-scenario sqlite snapshots, kept for
  diffing but not committed (large binaries, regeneratable from a
  rerun).
