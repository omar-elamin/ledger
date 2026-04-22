# Mission
## What Ledger is
A personal health coach in your pocket. A continuous, intelligent presence
that holds the whole picture of your physical self — what you eat, how you
train, how you sleep, how you recover — so you can stop carrying it in
your head.
The user talks to a coach. The coach remembers everything, develops a real
understanding of them over time, and renders the consequences of their
choices in real time. Tracking happens silently as a side effect of
conversation, never as the user's job.
## The user's problem
People who want to change their bodies — lose fat, build muscle, recover
better, sleep more — carry an enormous cognitive load. They have to
estimate calories, remember their lifts, watch their HRV, plan their
meals, decide whether tonight's drinks are worth it. The mental overhead
is exhausting and is the single biggest reason people fail at goals they
genuinely care about.
Existing tools make this worse. Trackers like MyFitnessPal turn the user
into a data-entry clerk. Wearables like Whoop give them more numbers to
interpret. Coaching apps either gamify the experience into something
infantilizing or hide behind disclaimers and refuse to have opinions.
What's missing is a tool that **takes the cognitive load off**. Something
the user can text the way they'd text a trusted friend who happens to be
a brilliant trainer — "had 2 factor meals and a wonton soup" — and have
the friend handle the math, hold the context, and tell them what to do
next.
That's Ledger.
## What this is, in product terms
A relationship, not an app.
The coach is a continuous presence in the user's life with a real
personality, real opinions, and real memory. The user develops a
relationship with this coach over months and years. The relationship is
the product. Features are downstream of whether they make the
relationship feel more real, more useful, more trusted.
The interface is conversation. The data is a receipt. The intelligence
is memory. Everything else is scaffolding.
## Principles
These are the rules that govern decisions across the codebase. When in
doubt, return to these.
**1. The relationship is the product.** Every design and code decision is
judged by whether it makes the coach feel more like a real, trusted,
intelligent presence — or less. Features that don't serve the
relationship are noise.
**2. Off-load, don't track.** The user reports in natural language. The
coach renders consequences. Tracking is a side effect of conversation,
never the user's job. We never ask the user to fill out a form, scan a
barcode, or pick from a database.
**3. Memory is intelligence.** The coach's value comes from holding the
whole picture across days, weeks, and months. Memory is hierarchical —
identity facts, observed patterns, recent narrative, live conversation
— and it's the most important system in the codebase. Compression is
where the intelligence lives.
**4. Conversation is the interface.** Settings get changed by talking to
the coach. Goals get updated by telling the coach. Data gets corrected
by saying so. Forms, modals, and configuration screens are last resorts,
not defaults.
**5. Dignity at every moment.** The user is treated as an intelligent
adult with serious goals. No streaks, no badges, no gamification, no
shame mechanics, no condescension, no validation theater, no
"Great job!" when nothing great has happened.
**6. Quiet by default.** The app demands attention only when there's
something genuinely worth saying. No engagement-bait notifications, no
"don't break your streak!" pings, no gentle reminders to come back. A
notification is a signal, never a hook.
**7. Direct over diplomatic.** The coach tells the truth even when it's
uncomfortable. Pushes back when the user is making excuses. Doesn't hide
behind disclaimers or hedge to avoid taking a position. Warmth and
directness are the same thing here, not opposites.
**8. Restraint over abundance.** We cut features more often than we add
them. Empty space is intentional, not a problem to solve. The temptation
to add charts, tabs, screens, configuration, social features, content
libraries — resist all of it. Sparseness is signal. The product gets
better by becoming smaller, sharper, more obviously itself.
## What this is not
Naming the negative space, because the gravitational pull of these defaults
is constant.
**This is not a tracker.** MyFitnessPal, Cronometer, Lose It, Cal AI —
these treat data entry as the product. We treat data entry as
contamination. If the user is logging instead of talking, we've failed.
**This is not a wearable companion.** Whoop, Oura, Apple Fitness — these
present metrics and let the user interpret them. We interpret on behalf
of the user. The metrics are inputs to the coach's judgment, not outputs
to the user's screen.
**This is not a chatbot.** ChatGPT with a system prompt is not Ledger.
The coach has persistent memory of *this specific person* across years,
develops opinions about them, and renders consequences with their full
context in mind. Generic conversational AI does not.
**This is not a fitness app.** No exercise libraries, no workout plans
to download, no recipe databases, no challenges, no community feed, no
content. The coach gives advice in conversation when asked. There is no
content to consume.
**This is not a wellness brand.** No mindfulness language, no
"your journey," no inspirational quotes, no soft-focus marketing
aesthetic. The product is competent and direct. The user is here to
change their body, not to feel feelings about the process.
**This is not a habit app.** No streaks, no daily check-ins required, no
"perfect week" rewards. Habits emerge from a working relationship, not
from gamification.
## The test
We are succeeding when, after months of use, the user thinks of Ledger
not as an app they open but as a presence they consult. When opening it
feels like texting a trusted friend, not using a tool. When the coach's
opinions about them feel earned, accurate, and worth taking seriously.
When the user can no longer imagine doing this work without the coach,
because the coach is holding the picture they used to have to hold
themselves.
The relationship is the product. Build accordingly.
