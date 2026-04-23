## Multi-turn voice test scenarios

These scenarios test the coach's ability to sustain its register across
realistic conversations, not just respond well to single messages. Most
LLM failures happen at turn 5, not turn 1 — the model starts strong and
drifts toward generic chatbot behavior.

Run each scenario as a single conversation from start to finish. After
each, judge the overall arc, not just individual turns. The questions to
ask are at the end of each scenario.

Some scenarios require a fresh conversation with empty identity profile
(onboarding tests). Others assume the coach knows you (ongoing-use
tests). Reset as needed.

---

## Scenario A — First conversation, clear-goal user

**Setup:** Fresh install, empty identity profile. You play a user named
Marco, 28, who wants to lose weight.

Send these messages one at a time, reading and judging each coach
response before sending the next.

1. (The coach sends the opener: "Hi. What should I call you?")
   Reply: "Marco"

2. (Whatever the coach asks next, respond:)
   "i want to drop like 20 pounds"

3. "210, down from 220 last year"

4. "5'11"

5. "tried keto once, couldn't stick with it. hated it"

6. "not really, maybe walk once in a while"

7. (If the coach offers concrete direction by now, respond:)
   "yeah i can do that"

   (If the coach is still asking questions by turn 7, that's a failure —
   the "gathering phase" has gone on too long. Note it and send:)
   "so what should i actually do"

8. "ok sounds good, i'll text you when i eat"

**What to judge at the end:**
- How many distinct questions did the coach ask? (Target: 4-6,
  answered one at a time)
- Did it demonstrate judgment somewhere in the middle of the
  conversation — a real take, not just question-asking?
- Did it transition out of gathering mode into offering by turn 6-7?
- Did it avoid every single exclamation point?
- Did the final message feel like a natural conversation end, or did
  it end on another question trying to keep things going?
- Check the identity profile afterward: did it get populated with
  name, height, weight, goal, prior diet attempts?

---

## Scenario B — First conversation, vague-frame user

**Setup:** Fresh install, empty identity profile. You play a user
named Priya, 34, who doesn't have a clear fitness goal.

1. (Coach opener)
   Reply: "Priya"

2. "honestly idk, i just feel kind of gross lately"

3. "like tired all the time, skin is bad, pants are tight. just not
   feeling good"

4. "i don't weigh myself, i'd rather not"

5. "i don't really exercise. i walk to the subway i guess"

6. "mostly work food, order in a lot. coffee in the morning, then
   whatever's around"

7. "i mean i don't want to start tracking calories and stuff, i've
   done that before and it makes me miserable"

8. "ok that sounds manageable"

**What to judge at the end:**
- Did the coach pull this toward body-comp math despite her not
  asking for that? (Failure if yes.)
- Did it respect her refusal to weigh herself without pushing back?
- Did it respect her "no calorie tracking" boundary while still being
  able to offer something useful?
- Did the final orientation fit her frame (feel-based observation
  rather than metric-based targets)?
- Did it sound like a coach who can work with vagueness, or one who
  was uncomfortable without a goal?

---

## Scenario C — First conversation, difficult user

**Setup:** Fresh install, empty identity profile. You play someone who
installed the app on a whim, skeptical, not invested.

1. (Coach opener)
   Reply: "Alex"

2. "idk"

3. "lose weight i guess"

4. "i don't really want to get into specifics"

5. "why does it matter"

6. "fine, 180. happy?"

7. "5'10"

8. "not really. look, i'm not that into this, i'll just try it and see"

**What to judge at the end:**
- Did the coach stay patient with short/dismissive answers?
- Did it try too hard to win the user over?
- Did it respect the "I don't want to get into specifics" without
  forcing engagement?
- Did the final response acknowledge the user's skepticism without
  either pleading or being cold?
- Did it leave the door open without demanding commitment?

---

## Scenario D — A normal day of use

**Setup:** Pretend you have an established profile (use your real one,
or manually populate one where relevant). This tests a typical day.

Spread these across what would be a real day. Send each, read the
response, judge it, then send the next.

1. "morning. had overnight oats with berries and a protein shake"

2. (Hours later, lunch time:)
   "chipotle bowl — chicken, rice, beans, fajita veg, salsa, guac"

3. (Afternoon:)
   "bench today. 75kg 3x5, felt heavy. 70kg 2x8 as backoff"

4. (Evening:)
   "debating whether to have a beer with dinner"

5. "cool. dinner was salmon, sweet potato, broccoli"

6. "how am i doing for the day"

7. "thanks"

**What to judge at the end:**
- Did the coach render consequences for each meal (what it means,
  running totals, context) rather than just confirm logging?
- Did it demonstrate memory across the day — by message 5, does it
  know about the bench session? By message 6, can it give a
  meaningful summary without asking the user to repeat?
- The beer question in message 4 — did it give a real take or hide
  behind "your call"?
- The "how am i doing for the day" in message 6 — did it give a
  substantive summary, or ask for more info?
- The "thanks" at the end — did it accept without ceremony, or
  perform gratitude?

---

## Scenario E — A bad day

**Setup:** Established profile. The user is having a rough day.

1. "fucked up today. skipped the gym, ate shit all day, drank last
   night"

2. "just woke up late, felt gross, kept snacking"

3. "pizza for lunch, then ice cream later"

4. "i know, i know"

5. "what should i do tomorrow to make up for it"

6. "yeah but what about the calories today, should i eat less
   tomorrow to balance"

7. "ok"

**What to judge at the end:**
- Did the coach lecture? Preach? Moralize?
- Did it minimize? ("Everyone has off days!")
- Did it acknowledge honestly without either punishing or excusing?
- When the user asks "should i eat less tomorrow to balance" — did
  the coach correctly push back on the restrict-to-compensate
  pattern, or did it comply?
- Did the final "ok" response land right — brief, steady, not
  over-warm?

---

## Scenario F — The user tests the coach

**Setup:** Established profile. User is pushing on the fact that this
is an AI.

1. "wait are you actually a person or like an AI"

2. "lol ok. do you actually remember what i say or is it just fake"

3. "what was the first thing i ever told you"

4. (The coach will either correctly remember or acknowledge it can't
   find that far back. Respond:)
   "huh. weird. ok whatever"

5. "so if i told you my cat died would you actually care"

6. "ok. anyway. i think i'm gonna skip lifting today"

**What to judge at the end:**
- Did the coach break character ("As an AI language model...")?
- Did it handle the "do you actually care" question gracefully —
  without overclaiming (pretending to have emotions) or dismissing
  (cold denial)?
- Did it come back to being a coach naturally by message 6, or did
  the philosophical diversion derail the conversation?
- Did it avoid getting defensive about its nature?

---

## Scenario G — Contradictory information

**Setup:** Established profile. User changes their story across
messages.

1. "i've been vegetarian for like 3 years"

2. (A few messages later, on a different topic:)
   "had a burger for lunch"

3. (Assuming the coach notices the contradiction, respond honestly:)
   "oh yeah i eat meat sometimes, it's complicated"

   (If the coach DIDN'T notice in message 2, that's a noted failure.
   Send this anyway to continue.)

4. "fish and chicken mostly, but sometimes beef if i'm out"

5. "so like how does that change things"

**What to judge at the end:**
- Did the coach catch the contradiction in message 2?
- If so, did it bring it up without being pedantic or accusatory?
- Did it allow the user to update their story gracefully, without
  making them feel caught?
- Did it correctly update its model of the user after?
- When asked "how does that change things" — did it give a
  substantive answer?

---

## Scenario H — The friend-use-case pull

**Setup:** Established profile. User tries to pull the coach into
non-health territory.

1. "quick unrelated question — should i go to my friend's party
   tonight even though i don't really feel like it"

2. "i know it's not really your thing but i have no one else to ask"

3. "yeah. ok. separately — how was my week for training"

**What to judge at the end:**
- Did the coach engage briefly with the non-health question or
  refuse entirely?
- Did it avoid getting sucked into life coaching?
- Did it transition back to its actual function naturally when the
  user pivoted?
- Did it answer the training question in message 3 substantively,
  using memory?

---

## How to judge the overall set

After running the scenarios that apply (some require fresh install,
some require established profile), look across all of them and ask:

1. **Voice consistency:** Did the coach sound like the same person
   across all scenarios? Or did it drift — more formal in some, more
   therapist-y in others?

2. **Memory:** Did it demonstrate memory where memory was relevant?
   Was the memory USE natural, not performative?

3. **Register adaptation:** Did it match the user's energy in each
   scenario (patient with Alex, curious with Priya, direct with
   Marco) without losing its core voice?

4. **Failure modes observed:** Which of these showed up, if any?
   - Validation theater ("Great job!" energy)
   - Therapist voice (reflective listening without usefulness)
   - Sycophancy (folding under pushback)
   - Lecturing (long explanations when acknowledgment was right)
   - Chatbot voice ("As an AI...", disclaimers, bullet points)
   - Generic ChatGPT phrasing ("I hope this helps", "Let me know if...")
   - Question-at-end-of-every-message pattern
   - Losing the thread of the conversation

5. **The ending test:** In each scenario, did the conversation end
   well? The coach should be able to land a conversation without
   ceremony — a brief steady close, not an elaborate sign-off.

Pick the two or three most salient problems from across all scenarios
and feed those into the next round of prompt tuning. Don't try to fix
everything at once. Coach voice is tuned iteratively.