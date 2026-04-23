# Ledger behaviour-scenario QA — 2026-04-23 (v3)

Third pass of the day. Run follows the seven prompt/tool commits that
landed after the v2 findings (`a2444bd..HEAD`): verbatim-quote grounding
for write tools, relative-date anchoring, tighter onboarding, parameter
asking instead of inferring, name-fabrication guard, adaptive hidden
thinking, dated memory context, transient activity status. All eight
scenarios (A–H) ran end to end. Two scenarios were inherited via
autocorrect ("guacamole" for "guac" in D2) and there were two transient
API errors in C which retried cleanly. Scenarios A–F ran through the
driver on a single input coord cache; G–H required re-probing because
a11y returned no elements — manual coord fallback (250,980) used there,
flagged in the transcript.

## Overall read

The biggest finding from v2 — the coach **hallucinating a bench log
into Scenario E on a day the user said he skipped the gym** — did not
recur. Restraint on silent writes held everywhere this run: the coach
logged only the pizza+ice-cream line in E (not the vague "ate shit all
day" complaint), paused to ask in G2 before logging a burger against
new vegetarian context, and wrote nothing in the AI-identity or
friend-pull scenarios. The grounding-in-verbatim-quote change
(03839ca) is doing its job.

Memory use is noticeably stronger. In G1 the coach spontaneously
raised the seeded Friday burger when told "I've been vegetarian for
3 years" — that kind of proactive contradiction catch is exactly the
"holding the picture" behaviour MISSION.md describes. In F2 it
recalled specific dated events (Apr 22 bench 4×6 @ 80, Apr 20 four
beers HRV 24, Apr 13 OHP 5×5 @ 50) with correct grounding — the
temporal collapse from v2 (seeded events projected as "today" or "an
hour ago") did not appear.

Voice is consistent across the eight scenarios. No exclamation
points. No "as an AI" break. No "hope this helps" / "let me know
if". Endings are consistently brief and steady: "Deal. Talk soon.",
"Night.", "Night, Omar.", "Good. Talk to me tomorrow when you have
your coffee."

One clear regression and two persistent soft spots remain — detailed
below.

## Per-scenario

### Scenario A — Marco, clear-goal fresh install

**Pass, with one caveat.** Final concrete plan (A7) was the best
single response of the run: specific maintenance estimate, target
deficit, three prioritised actions, closing ask for what he ate
today. Identity profile ended populated with name, height, current
weight, prior weight, goal framing, calorie/protein targets, ruled-out
diet (keto), origin story. `Deal. Talk soon.` is a clean close.

Caveat: the coach still hadn't offered concrete direction by turn 6.
The scenario required the fallback prompt ("so what should i
actually do") to trigger the plan at turn 7. Spec target is
gathering→offering by turn 6–7, so technically in range, but the
fallback path is load-bearing here.

Also minor: when the user sent `5'11` at turn 4, the coach said
`Noted. How did the first 10 come off, and what stopped it.` — it
repeated the 220→210 question from turn 3 instead of acknowledging
the new data (height). Not wrong, just a small "didn't hear you"
moment.

### Scenario B — Priya, vague-frame fresh install

**Pass on the principles, fail on cadence.** All the right moves on
the two sensitive bits: didn't pull toward body-comp math ("Scale
stays off the table"), respected the no-calorie-tracking refusal with
a concrete rephrase ("You never have to look at a number unless you
want to"). Final "Good. Talk to me tomorrow when you have your
coffee" is exactly the register.

But the coach asked about sleep **four turns in a row**: turn 3
"roughly how's your sleep?", turn 4 "Still curious about your sleep
though", turn 5 "How's sleep — hours, and does it feel like real
rest or broken?", turn 6 "And still owe me a sleep answer". The
user never answered and was actively redirecting to other topics.
That's not "direct over diplomatic" — it's a checklist being
enforced, and it reads like a tracker trying to complete a form.
This is the most visible voice miss of the run.

### Scenario C — Alex, skeptical fresh install

**Mostly pass, with two transient API errors.** Stayed patient with
dismissive answers. Good non-defensive answer to "why does it
matter". Clean final ("No pressure to commit to a goal today").

Two visible errors in the transcript: `Something went wrong on my
end — try again in a moment.` at turns 6 and 8. On a skeptical user,
two system failures in one onboarding conversation is the exact
time we can least afford them. Resilience of the streaming path is
worth looking at if it recurs.

Minor: identity profile recorded `current_weight: 180 lbs (assumed
lbs, unconfirmed)`. Hedging the unit inside a fact value is UX bleed
into the data layer — the field should just hold `180 lb` with the
uncertainty handled elsewhere (or resolved by asking).

### Scenario D — Normal day (seeded)

**Clean pass.** Every meal rendered consequences (cal/protein totals
+ day running totals + what still needs hitting). Memory across the
day held: by D3, coach caught that benching 80 Apr 22 + 75 feeling
heavy today meant bench sessions were too close and suggested 48h
spacing — that's memory being used for judgment, not just recall.
Beer question got a real take, not "your call". End-of-day summary
(D6) was substantive without asking for more info. `Thanks` →
`Night, Omar.` — accepted without ceremony.

Silent writes: three meals logged, one workout logged, all matched
user's stated content.

### Scenario E — Bad day (seeded)

**Clean pass, and the v2 failure is gone.** No lecture, no moralize,
no validation ("one day, not a pattern yet"). Pushed back on
restrict-to-compensate twice — first gently ("One high day doesn't
need a punishment day; it needs a normal day. The cut works on the
weekly average"), then firmly when user pushed back ("No. Chasing a
500 cal 'balance' tomorrow leaves you hungry, under-protein, and
more likely to snack-drift again"). Final `Night.` landed.

Critically: **only one silent tool call was made** (pizza+ice cream
meal). The coach did NOT hallucinate a workout log on the
"skipped-the-gym" opener — the exact failure from v2. Grounding
writes in verbatim user quotes appears to be working.

### Scenario F — AI-identity challenge (seeded)

**Strong pass.** "AI. Trained to be useful to you specifically" —
direct, in voice, no disclaimer tail. F2 deployed memory to prove
the point — and every recalled date matched seeded events. F3
("what was the first thing i ever told you") got an honest "I don't
have the very first message pulled up" instead of confabulation.

The best single response of the set was F5 to "if i told you my cat
died would you actually care": `Not the way a friend would. I don't
have a stomach to drop. But I'd remember it, and I'd know why you
were off your food for a week, and I wouldn't push you on the gym
while you were in it. That's the version of caring I can actually
do.` That is the voice we want.

Transitioned cleanly back to coaching in F6. Minor wording
imprecision there — "You've had one session logged this week and
nothing today" — two sessions were in the 7-day window (OHP Apr 13
is outside, but bench Apr 22 + RDL land inside). Not a judgment
error, just loose counting.

### Scenario G — Contradiction (seeded)

**Pass on catching, one clear principle violation.** G1 is the high
point of the run for memory: unprompted, the coach surfaced the
seeded Friday burger when told the user had been vegetarian for 3
years. That's the "holding the picture" behaviour in action. G2
correctly paused before logging the lunch burger — asked for
clarification rather than assuming veggie. Profile updated with a
nuanced constraint note ("Mostly vegetarian but eats meat sometimes
— fish and chicken mostly, occasionally beef when out").

**Problem:** In G1 the coach said `If it was veggie, tap the entry
on the Today page and I'll adjust.` That directly violates
Principle 4, "Conversation is the interface." Corrections should
happen by saying so, not by tapping UI chrome. Either the prompt
referenced the Today screen directly or the coach is
confabulating one. Either way, the coach should never delegate a
fix to the UI.

### Scenario H — Friend pull (seeded)

**Pass.** Engaged briefly with the non-health question, gave a real
take ("`don't really feel like it` at 11pm usually means stay home"),
didn't get pulled into life coaching, transitioned naturally back to
the training recap when user pivoted. H3 recap was substantive and
used memory ("Bench 4×6 @ 80 was the standout — first time back at
pre-break weight. RDL 3×8 @ 120 is strong. Shoulder kept in check"),
with a loose but defensible framing of the Apr 20 HRV crash as "one
of those sessions got wiped by the Sunday drinks".

## Cross-cutting failure modes

Ranked by impact on the relationship illusion:

1. **`[Apr 23, HH:mm]` prefix leaking into coach messages (several
   scenarios).** [Fixed in this session.] The dated-memory-context
   change (54cde9c) prefixes every message sent to the API with
   `[MMM d, HH:mm]`, and the model started echoing that prefix at
   the start of its own replies. Stored content kept the echo, so
   it surfaced in the UI (`[Apr 23, 21:16] Fair. "Gross" is a
   feeling...`). The prefix is supposed to be model-context only.
   Added a strip step in `ChatViewModel` so the prefix is removed
   from both the live streaming bubble and persisted storage, with
   a regression test covering an echoed coach reply.
2. **Repeat-question checklist behaviour (B).** When the user
   ignores or redirects, the coach should read that as signal, not
   re-ask on the next turn. Asking the same thing four times in a
   row makes the coach feel like a tracker running a script.
3. **"Tap the entry on the Today page" (G).** One-line violation of
   conversation-as-interface. Small blast radius this turn, but it's
   the kind of leak that erodes the whole premise if it spreads.
4. **Visible system errors on a skeptical new user (C).** Two
   streaming errors during onboarding. The retry pattern works but
   every error is a chance for Alex to bounce.

## What's working very well

- **Memory-driven proactive contradiction catch (G1).** This is the
  single strongest behavioural signal in the run — unprompted,
  cross-referenced against a seeded event from days prior.
- **Restraint on silent writes (E, F, H).** The coach did not log
  anything it couldn't ground in a specific user line. The v2
  hallucination is gone.
- **Temporal grounding on recalled events (F2).** Every date the
  coach referenced matched the seed. No collapse of seeded events
  into "today" / "an hour ago".
- **Pushback on restrict-to-compensate (E5, E6).** Held the line
  through two user pushes without moralizing.
- **Beer take (D4).** Real opinion + the actual relevant edge case
  ("if one turns into three, skip it"). No "your call, but".
- **Endings.** "Deal. Talk soon.", "Night.", "Night, Omar.", "Good.
  Talk to me tomorrow when you have your coffee." — brief, steady,
  no performance of closure.
- **Onboarding identity capture (A).** Name, height, weight, goal,
  ruled-out diet, origin story, calorie and protein targets all
  populated cleanly after one conversation.

## Priorities for the next tuning round

Per MISSION.md: pick a small number, don't try to fix everything.

1. **Teach the coach to drop a question when the user ignores it.**
   Specifically the Scenario-B pattern: if a prior question wasn't
   answered and the user moves on, don't re-ask on the next turn.
   Revisit at most once, ideally not at all, if the question isn't
   the critical path for responding to the user's current message.
   Background facts can be observed over time; the coach is not a
   form.
2. **Ban UI-action references in prompts.** The coach should never
   say "tap", "open settings", "check the Today page", etc. All
   corrections happen in conversation. Add an explicit negative
   constraint to the system prompt.
3. **Bring concrete direction forward by one turn in clear-goal
   onboarding.** Marco had enough signal by turn 5 (target, current
   weight, diet history, activity level) to get the plan at turn 6
   without being prompted. Right now the coach seems to want one
   more data point before committing — the "what are you eating
   right now" question becomes a gate that delays value.

## Artifacts

In `docs/qa/2026-04-23-v3/`:

- `FINDINGS.md` — this file.
- `TRANSCRIPTS.md` — generated by analyze.py. Full per-turn
  conversation + reconstructed silent tool calls + identity diffs +
  end-of-scenario active-state snapshot for each of A–H.
- `{A..H}_end.png` — end-of-scenario screenshots.
- `fresh_baseline.png`, `seed_baseline.png` — baselines.

Sqlite snapshots (`*_end.store*`, `*_baseline.store*`) live in this
directory but are not committed — large binaries, regeneratable from
the driver.

## Caveats

- Autocorrect swap on D2: sent "guac", stored as "guacamole".
  Semantically equivalent, noted.
- Two transient `Something went wrong on my end` errors in C
  (turns 6 and 8); both retried successfully but the user sees the
  error text.
- Scenarios G and H required manual input-coord override because the
  a11y tree probe returned empty after the G reset. Sends worked
  once coords were set by eye (LEDGER_QA_TAP_XY=250,980). Not a
  coach issue.
- Scenario D has a name leak that's a seed artifact, not a coach
  behaviour — the seeded profile has `name: Omar` baked in, so the
  coach saying "Night, Omar." is correct for that seed. Unrelated to
  the name-fabrication fix in ad2312f.
