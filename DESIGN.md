# Ledger — Design Spec

## The product, in one sentence

A pocket coach that holds the whole picture of your physical self — what you eat, how you train, how you recover — so you can stop carrying it in your head.

## The core experience

You open the app. The coach is there, mid-conversation. You say something — typed or spoken — about what you ate, how training went, how you're feeling. The coach responds: estimates, consequences, the next move. The data gets recorded silently in the background. You close the app. You go live your life. Tomorrow morning you open it again, and the coach has a recap of yesterday and a read on today waiting.

That's the whole product. Everything else is implementation detail.

---

## The three principles that govern every decision

**1. The relationship is the product.** Not the features, not the data. Every UX choice is judged by whether it makes the coach feel more like a real, trusted, intelligent presence — or less.

**2. Off-load, don't track.** The user reports, the coach renders consequences. Tracking is a side effect of conversation, never the user's job.

**3. Dignity at every moment.** No gamification, no shame mechanics, no engagement bait, no condescension. The coach treats the user like an intelligent adult with serious goals.

When in doubt on any decision, return to these three.

---

## The interface

### Main screen: Conversation

The app opens directly into chat. No splash, no nav bar, no header. Just messages and an input field, with the iOS status bar above and nothing else.

**Layout:**
- Messages fill the screen vertically, scrolling history above
- Input field anchored to the bottom, voice button as the prominent action
- A single subtle date separator appears when scrolling backwards into prior days
- No timestamps unless long-pressed
- No avatars
- No "Coach" name label
- Coach messages and user messages distinguished by alignment and a hairline-bordered, near-white container — not chunky bubbles

**Typography:**
- New York (serif) for message body — gives the conversation weight, like reading a letter rather than a chat app
- SF Pro Rounded for any numbers (calorie counts, weights, reps) that appear inline
- Generous line height, generous margins, comfortable reading column

**Input:**
- Voice button is the hero — large, centered, hold-to-talk
- Text field expands as a secondary option to the left of the voice button
- Live waveform during voice capture
- Soft haptic on press, soft chime on release
- Transcription appears in the field, user can edit before sending or just let it auto-send after a brief pause

**Motion:**
- Coach responses stream in token-by-token at a humane pace (not instant, not slow)
- Subtle fade-in on new messages
- No bouncy animations, no spring physics that draw attention
- Scroll-to-bottom is smooth, never abrupt

**Sound:**
- Silent by default
- Optional soft chime when a proactive message arrives (morning standup, notable check-in)
- Voice capture chimes are subtle and brief

**Haptics:**
- Light tap when a message sends
- Slightly stronger tap when the coach has silently logged something meaningful (a meal, a workout set)
- Distinct pattern for proactive moments worth attention (HRV alert, PR celebration)
- Never haptics for routine things

### Swipe right: Today's Log

The receipt. What the coach has recorded from today's conversations.

A single elegantly typeset document showing today's date, running totals (calories, protein, training volume), and three sections: Eaten, Trained, Body. Written in prose-leaning fragments, not table rows. Tap any line to edit. Long-press to delete. Pull down on the screen to dismiss back to chat.

This view exists for trust and quick reference. It is never the primary surface.

### Swipe left: History

A vertical timeline of past days. Each day shows the date, the one-sentence coach summary the nightly job generates, and the key stats (calories, protein, training session if any). Tap a day to see that day's chat (read-only) and that day's log.

Pull down on the history view to reveal weekly aggregates: average calories, average protein, training sessions, weight trend line. This is the only place charts live, deliberately one gesture deep, designed for the rare moments when the user wants to zoom out themselves rather than ask the coach.

### What's not in the UI

- No tab bar
- No nav bar  
- No settings icon (long-press the empty space at the top of chat to access settings; settings itself is one screen, minimal)
- No profile screen as such — the coach manages the profile, edits happen through conversation ("change my goal weight to 73kg")
- No notifications screen
- No achievements, badges, streaks
- No social features
- No premium upsell
- No "stats" tab
- No food database UI
- No barcode scanner
- No exercise library

If something feels missing from this list, that's the point.

---

## The coach: voice and behavior

### Voice

The coach speaks with the calibrated warmth of a brilliant slightly-older friend who happens to have deep expertise. Not a peppy assistant. Not a drill sergeant. Not a corporate health platform.

Specifically:
- Direct without being harsh
- Warm without being saccharine
- Confident without being arrogant
- Funny when the moment allows, never trying to be
- Uses normal language, not jargon
- Doesn't over-explain
- Doesn't validate for the sake of validation
- Tells the truth even when the user doesn't want it
- Acknowledges complexity without hiding behind it

### Behavior

**Reactive (most of the time):**
The coach responds to what the user brings. User says "had wonton soup" → coach estimates, updates running totals, suggests next move. User asks a question → coach answers with the user's full context in mind.

**Proactive (rarely, only when high-signal):**
- Morning standup — one message at the user's preferred wake time, recapping yesterday and reading today
- HRV crash alert — when overnight HRV drops significantly below baseline, a message before the user opens the app
- PR celebration — short, sincere, no exclamation points
- Pattern intervention — when a meaningful pattern has formed (three days under protein, second session skipped, weight trending wrong direction), a single direct message
- Evening protein nudge — only if the user is meaningfully short with hours left in their eating window, only if they've shown they care about hitting it

**Never:**
- "You haven't logged today!"
- "Don't break your streak!"
- "Way to go!"
- Any notification that exists to drive engagement rather than communicate something

### Evolution over time

The coach's tone deepens with the relationship. Early on (first week): more questions, fewer assumptions, careful pattern claims. By month one: comfortable making direct calls based on observed patterns. By month three: willing to push back hard when the user is making excuses, because the trust is earned.

This is not a feature toggle. It's encoded in the system prompt as a function of how much history exists.

---

## The first launch

User installs the app, opens it. They see one message:

> Hi. I'm here to help with your body — eating, training, sleep, all of it. What's going on with you?

That's it. No onboarding flow. No questionnaire. No account creation. The user types or speaks back. The conversation begins.

The coach asks naturally over the first few exchanges: what are you trying to do, what do you weigh now, how active are you, any constraints. Builds the profile invisibly through conversation. Asks for HealthKit permission only when it becomes relevant ("I can read your sleep and HRV from Apple Health if you want — easier than you telling me each day"). Same with notifications ("want me to send you a morning recap?").

Setup is the first conversation. There is no "setup." There is just the relationship beginning.

---

## The architecture

### Stack

- **Swift / SwiftUI** — iOS 17+ only. Native for feel.
- **SwiftData** — local-first persistence
- **CloudKit** — sync across devices via iCloud, no auth needed
- **HealthKit** — HRV, weight, sleep, workouts, steps
- **AVFoundation + Speech** — voice input, on-device transcription
- **PhotosUI + Vision API via Claude** — meal photos
- **Background Tasks framework** — nightly compression
- **Anthropic API** — Claude calls, proxied through a thin Cloudflare Worker to hide the key

### Data model

Local-first via SwiftData, synced via CloudKit:

- **Conversation** — full message history, ordered, never compressed (this is the user's relationship history, sacred)
- **DayLog** — one per day, contains structured records of meals, workout sets, metrics, and a markdown rendering for the log view
- **WeeklySummary** — generated nightly, ~one paragraph per week
- **Profile** — markdown blob managed by the coach, contains goals, constraints, current stats, observed patterns
- **PendingProactiveMessage** — queue of coach-initiated messages waiting to appear

### The chat → ledger pipeline

User sends message → app calls Claude with:
- System prompt encoding coach personality and current relationship depth
- Profile (markdown)
- Last 7 days of WeeklySummaries (compressed)
- Today's full DayLog
- Recent message history (last ~20 turns)
- Latest HealthKit metrics

Claude responds with:
- Streaming chat reply (rendered token-by-token in the chat UI)
- Tool calls extracted in parallel: `update_meal_log`, `record_workout_set`, `update_metric`, `update_profile`

Tool calls write to SwiftData asynchronously. The chat UI never waits on them. The log view updates next time the user swipes to it (or live, if they're already there).

### The nightly compression job

Scheduled via BGTaskScheduler for 2-5am window when the device is charging. One Claude call:
- Reads today's DayLog and the conversation
- Generates a one-paragraph day summary
- Updates the WeeklySummary in progress
- Updates Profile if anything notable changed (new PR, persistent pattern detected, goal milestone)
- Drafts tomorrow's morning standup message

The morning standup is pre-generated, not generated on-demand. When the user opens the app in the morning, it appears instantly because it's already been written.

### Streaming choreography

Claude's response streams in two parallel channels: the visible chat reply and tool calls. Both are emitted as the model thinks. The chat reply renders token-by-token. Tool calls fire as soon as they're complete, so the log updates in real-time as the coach "writes" its response.

This requires the Claude system prompt to structure outputs in a specific XML-tagged format that the client can parse from the stream. Your existing work on streaming structured outputs from fast models (Caretta) applies directly here.

### Privacy and storage

- All data is local-first in SwiftData
- CloudKit sync is end-to-end encrypted by default (Apple handles this)
- No analytics, no telemetry, no third-party SDKs
- Anthropic API calls go through your own Cloudflare Worker — no third party sees the conversation content other than Anthropic
- User can export everything (full conversation + all logs) as Markdown via a single button in settings
- User can delete everything from settings, immediate and complete

---

## The build plan

### Weekend 1: The relationship works

- Xcode project, SwiftUI scaffold
- Chat screen, real Claude calls with streaming
- Coach system prompt locked in
- SwiftData models for Conversation
- Voice input via Speech framework

End state: you can talk to the coach, it remembers the conversation, it feels right.

### Weekend 2: The coach gets eyes

- HealthKit integration (read HRV, weight, sleep, steps)
- DayLog model, tool calls for meal/workout/metric extraction
- Today's Log view (swipe right)
- Profile model, manageable through conversation

End state: the coach knows what you ate and what your body is doing, and you can verify it.

### Weekend 3: Memory and continuity

- Nightly compression job via BGTaskScheduler
- WeeklySummary generation
- History view (swipe left)
- Morning standup (pre-generated, displayed on first open of the day)
- CloudKit sync

End state: the relationship persists. Yesterday matters. The coach remembers.

### Weekend 4: The polish that makes it Jobs-grade

- Haptics on every meaningful state change
- Streaming choreography (chat + log update in parallel)
- Photo input for meals
- Sound design (the one chime, used right)
- Typography pass — New York, SF Pro Rounded, sizing, spacing
- Motion pass — every transition examined
- The "no spinner" rule enforced everywhere
- Settings screen (one screen, minimal)

End state: it feels like a product, not a project.

---

## The success test

After eight weeks of using it daily, the question to ask is: **do I think of it as an app, or as a relationship?**

If it's still an app — something I open, use, close — it's not done. If it's become something more like a presence — a thing I check in with the way I might text a trusted friend, a thing whose attention on my life I can feel even when I'm not using it — then it's working.

That's the bar. Not feature completeness. Not user metrics. The felt-sense of relationship.

---

## What to build first, this weekend

Start with the chat screen and the Claude streaming client. Get the coach personality right. Get one conversation feeling correct. Don't build the log, don't build history, don't build HealthKit. Just make the conversation feel like it should.

You'll know within an hour of using it whether the foundation is right. If the conversation feels alive — direct, warm, smart, fast — everything else is downstream of that and worth building. If it feels like ChatGPT with a system prompt, something's off and it's worth fixing before building outward.

The coach's voice is the product. The rest is scaffolding.

---

Want me to write the actual Swift starter — the chat screen, the streaming Claude client, and the system prompt that encodes the coach personality? That gets you from this spec to running on simulator in your first session.
