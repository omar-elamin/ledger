# Ledger Memory System — Architectural Briefing

This document describes the Ledger app's memory system as it exists in
the current codebase (branch `main` at time of writing). It is a
description of what is implemented, not a specification of intent.

## 1. Overview

Ledger stores every user/coach turn, every meal, every training set, and
every body/recovery metric the user logs through the coach. On top of
that raw log it maintains several generated summaries at different time
spans — an "active state" snapshot covering the last ~7 days, a daily
narrative paragraph per day, a 28-day running set of those daily
summaries, rolled-up weekly and monthly paragraphs beyond that window, a
durable identity-facts markdown document, and a small list of pattern
observations with confidence levels. Every coach chat pulls a single
concatenated "## Memory" block built from those layers and prepends it
to the coach system prompt. A nightly background job regenerates the
active-state snapshot and daily summary; a weekly pass refreshes
patterns and proposes identity updates; archive roll-ups compress older
days into weeks and older weeks into months.

## 2. The levels of memory

The code does not label these with explicit "Level N" markers in model
types, but `MemoryMaintainer`'s system prompts do (Level 1, Level 1.5,
Level 2, Level 3). The levels are:

### Level 1 — Identity (`IdentityProfile`)
- **Purpose:** Durable identity material about the user — not only atomic facts (name, age, body, numeric targets) but also the way they frame their goal, the constraints they operate under, approaches they've tried, and rule-outs. Framings can be multi-sentence and preserve the user's own language.
- **Backing model:** `IdentityProfile` (singleton row, `scope == "default"`). Content is a markdown document with sections (`## Goals`, `## Body`, `## Constraints`, `## Preferences`, `## Lifestyle`, `## Other`), each containing `- key: value` bullets. Parsing/rendering handled by `IdentityProfileDocument` in `Ledger/Models/Persistence.swift:637-782`. The section a key lands in is decided by keyword matching in `IdentityProfileDocument.section(forKey:)` (e.g. `goal_framing`, `goal_weight`, `calorie_target` → Goals; `constraint`, `ruled_out` → Constraints; etc.).
- **Update cadence:** Real-time (coach `update_identity_fact` tool writes directly). Also a weekly "propose updates" pass via `MemoryMaintainer.proposeIdentityUpdates()`; only `factual` + `high` confidence proposals are applied, other proposals are logged but not persisted.
- **Loaded into every chat context:** Yes, under the heading "## Who this person is".
- **Approximate size:** Unbounded in principle. With framings included, the profile can stretch to several hundred tokens; still low in absolute terms.

### Level 1.5 — Patterns (`Pattern`)
- **Purpose:** Durable behavioral patterns observed across recent days, filtered by a utility test — a pattern is only worth storing if it would change how the coach responds to a future message. Low/medium/high confidence calibrated to observation count (3-5 / 6-10 / 10+).
- **Backing model:** `Pattern` (many rows, unique `key`).
- **Update cadence:** Weekly (on Sundays, or whenever >7 days since last weekly pass) via `MemoryMaintainer.updatePatterns()`. The LLM returns JSON `operations` (`add` / `update` / `remove`). Both the current patterns and the last 28 daily summaries are passed to the prompt so patterns accumulate rather than regenerating; the prompt explicitly instructs to reinforce, lower-confidence, or remove existing patterns based on new evidence, and to lower confidence on patterns not reinforced in 8+ weeks.
- **Loaded into every chat context:** Only `medium` and `high` confidence patterns, under "## Patterns observed".
- **Approximate size:** Small — a handful of single-line bullets, <100 tokens typically.

### Level 2 — Active state (`ActiveStateSnapshot`)
- **Purpose:** A prose situational brief — 4-6 sentences characterizing where the user is right now relative to their goal, the trend, anything notable, and what the coach doesn't have enough data to say. Not a bullet readout; the prompt explicitly names the "data readout" style as a failure mode.
- **Backing model:** `ActiveStateSnapshot` (singleton, `scope == "default"`).
- **Update cadence:** Nightly via `MemoryMaintainer.updateActiveState()`. A Swift-side pre-computation pass (`computeActiveStateEnrichment`) runs before the LLM call and hands it a structured `ActiveStateEnrichment` block — goal frame, weight trend (7-day mean + delta vs prior 7, 28-day mean + delta), intake averages + deltas vs target, training block, recovery block (HRV baseline only after 14+ days of data), data-sufficiency flags — so the LLM's job is characterization, not arithmetic.
- **Loaded into every chat context:** Yes, under "## Where they are right now".
- **Approximate size:** 4-6 sentences of prose, capped at 700 output tokens; typically well under.

### Level 3 — Recent daily summaries (`DailySummary`)
- **Purpose:** One ~40-word paragraph per day capturing concrete facts and tone.
- **Backing model:** `DailySummary` (one row per day, unique `date`, plus embedded `SummaryKeyStats`).
- **Update cadence:** Nightly (current day) via `MemoryMaintainer.summarizeToday()`. Days older than 28 days get absorbed into `WeeklySummary` and the source `DailySummary` rows are deleted by `rollupWeek()`.
- **Loaded into every chat context:** Yes — most recent 28 summaries, sorted ascending, under "## Recent days".
- **Approximate size:** ~40 words × up to 28 days ≈ 1000–1500 tokens.

### Today-so-far (not labeled with a level)
- **Purpose:** Render today's raw logged meals, workouts, and metrics.
- **Backing models:** `StoredMeal`, `StoredWorkoutSet`, `StoredMetric`, filtered to the current day.
- **Update cadence:** Real-time (built fresh on each chat send).
- **Loaded into every chat context:** Yes, under "## Today so far".
- **Approximate size:** Variable; typically small (under a few hundred tokens).

### Archive — Weekly summaries (`WeeklySummary`)
- **Purpose:** Rolled-up paragraph for a single ISO week.
- **Backing model:** `WeeklySummary` (unique `startDate`, embedded `SummaryKeyStats`).
- **Update cadence:** Nightly via `MemoryMaintainer.rollupWeek()`; eligible when the week's end is ≥ 28 days before today. Consumes and deletes the source `DailySummary` rows.
- **Loaded into every chat context:** No — only reachable via the `search_archive` tool (substring match, see §8).

### Archive — Monthly summaries (`MonthlySummary`)
- **Purpose:** Rolled-up paragraph for a calendar month.
- **Backing model:** `MonthlySummary` (unique `startDate`).
- **Update cadence:** Nightly via `MemoryMaintainer.rollupMonth()`; eligible when the month's end is before the current month's start. Consumes and deletes the source `WeeklySummary` rows.
- **Loaded into every chat context:** No — only via `search_archive`.

### Not yet implemented
- **Morning standup:** `MemoryMaintainer.preGenerateMorningStandup()` exists but is a stub (`logger.debug("Morning standup generation is still a stub.")`, `MemoryMaintainer.swift:614-616`).
- **WeeklySummary narrative for History view:** A `// TODO` in `MemoryMaintainer.swift:65-68` notes that `WeeklySummary` narratives are not yet wired into `HistoryView`. Today `HistoryView` renders narratives from `MockHistoryNarratives` (`Ledger/MockData/MockHistory.swift`), not from `WeeklySummary.summaryText`.

## 3. Data models

All memory-related `@Model` classes live in `Ledger/Models/Persistence.swift`. The current schema is `LedgerSchemaV2`; top-level typealiases make the V2 types the app-wide names. `LegacyLedgerSchema` (pre-V1) and `LedgerSchemaV1` exist only for migration.

### `SummaryKeyStats` (struct, Codable)
File: `Ledger/Models/Persistence.swift:4-18`
```swift
struct SummaryKeyStats: Codable, Equatable, Sendable {
    var calories: Int
    var protein: Int
    var trained: Bool
    var hrv: String?
    var sleep: String?

    static let empty = SummaryKeyStats(
        calories: 0, protein: 0, trained: false, hrv: nil, sleep: nil
    )
}
```

### `PatternConfidence`
File: `Ledger/Models/Persistence.swift:20-24`
```swift
enum PatternConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}
```

### `StoredMessage` (V2)
File: `Ledger/Models/Persistence.swift:403-415`
- `var id: UUID`
- `var role: String` (`"user"` or `"coach"`)
- `var content: String`
- `var timestamp: Date`
- No relationships.

### `StoredMeal` (V2)
File: `Ledger/Models/Persistence.swift:418-438`
- `var id: UUID`
- `var date: Date`
- `var descriptionText: String`
- `var calories: Int`
- `var protein: Int`
- No relationships.

### `StoredWorkoutSet` (V2)
File: `Ledger/Models/Persistence.swift:441-461`
- `var id: UUID`
- `var date: Date`
- `var exercise: String`
- `var summary: String`
- `var notes: String?`
- No relationships.

### `StoredMetric` (V2)
File: `Ledger/Models/Persistence.swift:464-484`
- `var id: UUID`
- `var date: Date`
- `var type: String` (free-text, but tool enum restricts to `hrv|sleep|weight|mood|other`)
- `var value: String`
- `var context: String?`
- No relationships.

### `IdentityProfile` (V2)
File: `Ledger/Models/Persistence.swift:487-503`
- `@Attribute(.unique) var scope: String` (constant `"default"`)
- `var markdownContent: String` (structured markdown, see `IdentityProfileDocument`)
- `var lastUpdated: Date`
- `static let defaultScope = "default"`
- No relationships. Parsed/rendered by `IdentityProfileDocument` (static enum, `Persistence.swift:637-782`) — provides `upserting(key:value:into:)`, `merging(markdown:with:)`, `facts(from:)`, `sections(from:)`, and a keyword-based `section(forKey:)` that bucket keys into one of `Goals | Body | Constraints | Preferences | Lifestyle | Other`.

### `Pattern` (V2)
File: `Ledger/Models/Persistence.swift:506-529`
- `@Attribute(.unique) var key: String`
- `var descriptionText: String`
- `var evidenceNote: String`
- `var confidence: PatternConfidence`
- `var firstObserved: Date`
- `var lastReinforced: Date`
- No relationships.

### `ActiveStateSnapshot` (V2)
File: `Ledger/Models/Persistence.swift:532-548`
- `@Attribute(.unique) var scope: String` (constant `"default"`)
- `var markdownContent: String`
- `var generatedAt: Date`
- `static let defaultScope = "default"`
- No relationships.

### `DailySummary` (V2)
File: `Ledger/Models/Persistence.swift:551-568`
- `@Attribute(.unique) var date: Date` (start-of-day)
- `var summaryText: String`
- `var keyStats: SummaryKeyStats`
- `var createdAt: Date`
- No relationships (rows get deleted once folded into `WeeklySummary`).

### `WeeklySummary` (V2)
File: `Ledger/Models/Persistence.swift:571-591`
- `@Attribute(.unique) var startDate: Date` (start of ISO week)
- `var endDate: Date`
- `var summaryText: String`
- `var keyStats: SummaryKeyStats`
- `var createdAt: Date`
- No relationships.

### `MonthlySummary` (V2)
File: `Ledger/Models/Persistence.swift:594-614`
- `@Attribute(.unique) var startDate: Date` (start of calendar month)
- `var endDate: Date`
- `var summaryText: String`
- `var keyStats: SummaryKeyStats`
- `var createdAt: Date`
- No relationships.

### Schema bookkeeping
- `LegacyLedgerSchema` (`Persistence.swift:26-135`) defined `StoredMessage`, `StoredMeal`, `StoredWorkoutSet`, `StoredMetric`, and a key-value `ProfileEntry`. Used only for legacy-store recovery in `LedgerPersistentModels.recoverLegacyStoreIfNeeded`.
- `LedgerSchemaV1` (`Persistence.swift:137-382`) introduced `IdentityProfile`, `Pattern`, `ActiveStateSnapshot`, `DailySummary`, `WeeklySummary`, `MonthlySummary`, but kept `ProfileEntry`.
- `LedgerSchemaV2` (`Persistence.swift:384-615`) drops `ProfileEntry`; V1→V2 migration (`LedgerSchemaMigrationPlan.migrateLegacyProfileEntries`) folds `ProfileEntry` rows into `IdentityProfile.markdownContent` and deletes the entries.

## 4. Context assembly

Path: `Ledger/Services/ContextBuilder.swift` + caller in `Ledger/ViewModels/ChatViewModel.swift`.

When the user sends a chat message, `ChatViewModel.runSend(_:modelContext:)` (`ChatViewModel.swift:68-114`) constructs a fresh `ContextBuilder` with the current `ModelContext`, calls `.buildChatContext()`, and passes the resulting string to `ClaudeClient.streamMessage` under the `contextBlock` argument. `ClaudeClient.streamMessage` then wraps it with `CoachPrompt.systemPrompt(contextBlock:)` (`ClaudeClient.swift:116`), which inlines the block under a `## Memory` heading at the end of the coach system prompt.

`ContextBuilder.buildChatContext()` (verbatim, `ContextBuilder.swift:19-28`):

```swift
func buildChatContext() -> String {
    let sections = [
        "## Who this person is\n\(identityContent())",
        "## Patterns observed\n\(patternsContent())",
        "## Where they are right now\n\(activeStateContent())",
        "## Recent days\n\(recentDaysContent())",
        "## Today so far\n\(todayMarkdown())"
    ]
    return sections.joined(separator: "\n\n")
}
```

Each section is assembled separately:

- `identityContent()` — fetches the single `IdentityProfile` where `scope == "default"` and returns its `markdownContent` verbatim, or `"No stable identity facts recorded yet."` if absent/empty.
- `patternsContent()` — fetches all `Pattern` rows sorted by `lastReinforced` desc, filters to `medium|high`, renders one line each as `"- [<confidence>] <descriptionText> Evidence: <evidenceNote>"`. Empty list → `"- None yet."`.
- `activeStateContent()` — fetches the single `ActiveStateSnapshot` where `scope == "default"` and returns its `markdownContent`, or `"No active state snapshot yet."`.
- `recentDaysContent()` — fetches most recent 28 `DailySummary` rows (sorted ascending), renders each as `"<EEE MMM d>: <summaryText>"`. Empty → `"No daily summaries yet."`.
- `todayMarkdown()` — fetches today's `StoredMeal`, `StoredWorkoutSet`, `StoredMetric` rows in `[startOfDay, startOfDay+1)`. If all empty → `"Nothing logged yet today."`. Otherwise emits (in this order): `"Meals total: <cal> cal, <protein>g protein"`, each meal bulleted via `LogTextFormatter.mealLine`; a blank line then `"Training"` with each workout via `LogTextFormatter.workoutLine`; a blank line then `"Body / recovery"` with each metric via `LogTextFormatter.metricLine`.

### Shape of the final context block

The final string is five sections separated by blank lines, e.g.:

```
## Who this person is
## Goals
- goal_weight: 75kg
- goal_framing: Want to get back to feeling strong and lean — same body I had before the ankle injury sidelined me in summer 2025.
- calorie_target: 1900
- protein_target: 160

## Body
- height: 183cm
- current_weight: 82.6kg

## Constraints
- constraint: Travels internationally roughly one week a month — consistent logging lapses on those trips.

## Patterns observed
- [medium] Protein tends to lag on social days. Evidence: Repeated across recent social days with protein under 130g.

## Where they are right now
Omar is 3 weeks into a cut from 83kg toward 75kg, rebuilding training after a 9-month break. 7-day average 82.6kg, down 0.4kg from last week — on track for the timeline he set. Eating averages 2,180 cal and 138g protein, both under targets of 1,900 and 160g. Bench is at 60kg for 3×6, early restart. HRV baseline still forming, only 5 days of data.

## Recent days
Wed Apr 16: Steady day. Hit targets without effort — 2,050 cal, 130g protein. Bench moved well at 55kg for 3×5. Nothing to flag.
Thu Apr 17: Social dinner pulled protein low again — 2,310 cal but only 122g. Logged it and moved on.
…

## Today so far
Meals total: 1200 cal, 110g protein
- 2 Factor meals + 200g chicken (~1200 cal, 110g protein)

Training
- Bench press  3×5 @ 100kg  Moved well

Body / recovery
- HRV 24 (low after drinks)
```

Then `CoachPrompt.systemPrompt(contextBlock:)` places this block under the line `## Memory` as the final part of the system prompt, followed by `"Respond to their next message now."`.

## 5. Maintainer jobs

All maintainer jobs are methods on `actor MemoryMaintainer` in `Ledger/Services/MemoryMaintainer.swift`. They consume structured SwiftData, encode it to JSON as the user prompt, call `textGenerator.generateText(systemPrompt:userPrompt:maxTokens:)`, and write results back to SwiftData. In production, `textGenerator` is `ClaudeClient`; in UI tests it's `ScriptedMemoryTextGenerator`.

### `updateActiveState()` — Level 2 snapshot
- **File:** `Ledger/Services/MemoryMaintainer.swift:339-385`
- **Input:** Last 7 days of structured data plus today, plus a pre-computed enrichment block. Builds `ActiveStatePromptInput` containing `windowStart`, `windowEnd`, `todayMarkdown`, per-day `DailyStatSnapshot`s, `latestMetrics` (most recent metric per `type.lowercased()`), training/logging streak lengths, `workingWeights` (latest working weight per exercise, parsed out of `StoredWorkoutSet.summary` via regex in `MemoryMaintainer.parseLoadText`), and `preComputedContext: ActiveStateEnrichment` produced by `computeActiveStateEnrichment` (`MemoryMaintainer.swift:1000-1038`). The enrichment block contains: `GoalFrameBlock` (framing/origin/approach pulled from identity facts, goal-weight gap, days since goal start, calorie/protein targets), `WeightTrendBlock` (7-day mean vs prior 7-day mean, 28-day mean and delta, insufficiency notes when fewer than 3 weigh-ins in 7d or 8 in 28d), `IntakeBlock` (7-day calorie/protein means and deltas vs target), `TrainingBlock`, `RecoveryBlock` (HRV mean + stddev only when 14+ days available, sleep means, notes when data is thin), `DataSufficiencyBlock` (flags like `goal_weight not set`, `hrv_baseline_not_established (N days)`).
- **Output:** Prose situational brief (4-6 sentences); upserts the singleton `ActiveStateSnapshot` with the returned text and `generatedAt = now()`.
- **Trigger:** First step of every nightly run (and first step of every forced run).
- **`maxTokens`:** 700.
- **System prompt (verbatim, `MemoryMaintainer.swift:6-63`):**

```
You are writing a situational brief for a coach taking over this
person's case. The coach reads this on every chat turn to ground
their next response, so it must characterize the situation, not
list its components.

Write 4-6 sentences, woven together as natural prose — not a bullet
list, not sections. Cover these five areas in whatever order reads
best:

1. The goal frame — what they are trying to do and how long they
   have been at it
2. Current state relative to that goal — where they are now
3. Trend — direction things are moving, if discernible
4. Anything notable the coach should keep in mind (an anomaly, a
   sustained deviation, a recent pivot)
5. Data sufficiency flags — what we don't yet have enough of to say

Write in the coach's voice. Direct, specific, no filler. Do not
editorialize: no "crushing it," no "struggling," no motivational
framing. State observations. Inline numbers naturally ("82.6kg
averaged over 7 days, down 0.4kg from last week"), not as a readout.

## Example of a good brief

"Omar is 3 weeks into a cut from 83kg toward 75kg, rebuilding
training after a 9-month break. Current 7-day average 82.6kg —
down 0.4kg from last week, on track for his timeline. Eating
averages 1,850 cal and 138g protein, both slightly under targets
of 1,900 and 160g. Bench at 50kg for 3×5, target 85kg — muscle
memory should make this fast. HRV baseline still forming, only 5
days of data. No issues flagged."

## Example of a bad brief (do NOT produce output like this)

"Current weight: 83kg. Goal: 75kg. Training: restarting, currently
at 50kg bench. Eating 1,200 cal/day, 130g protein/day."

The bad version lists values. The good version characterizes a
situation. That difference is the entire point of this brief.

## How to use the input

The user message below contains a structured pre-computed context
block. Every delta, trend, baseline, and data-sufficiency flag
has already been computed — you do not need to do arithmetic.
Your job is characterization: read the computed fields, pick the
ones that matter for this person right now, and weave them into
prose.

If a field is null or flagged as insufficient data, do not invent.
Name the gap if it matters (e.g. "HRV baseline still forming"),
or leave it unmentioned if it doesn't.

## Output

Return only the brief prose. No headers, no labels, no preamble.
```

### `summarizeToday()` — Level 3 daily summary
- **File:** `Ledger/Services/MemoryMaintainer.swift:387-439`
- **Input:** Today's `StoredMeal`/`StoredWorkoutSet`/`StoredMetric` via `ContextBuilder.structuredData`, plus all `StoredMessage` rows timestamped inside today's bounds, plus today's markdown render, plus a pre-computed `DailyEnrichment`. Sent as `DailySummaryPromptInput { date, keyStats, todayMarkdown, messages: [ConversationSnippet(role, content)], preComputedContext: DailyEnrichment }`. The enrichment is produced by `computeDailyEnrichment` (`MemoryMaintainer.swift:1239-1317`) and contains: today's calorie/protein deltas vs identity-profile targets, baseline classification against the prior 7 days (`high`/`low`/`normal` at 15% tolerance for intake, 15% for HRV, 10% for sleep), HRV baseline mean (only populated once 7+ prior HRV readings exist), sleep-vs-baseline classification (only when 5+ prior readings), per-exercise `TrainingProgressionNote` comparing today's load against the most recent prior session of the same exercise (`up`/`down`/`flat`/`baseline`/`unknown` — direction computed via `loadNumeric` regex parse), and a set of `conversationFlags` extracted by keyword matching against today's messages and log descriptions (`alcohol_mentioned`, `travel_mentioned`, `social_event_mentioned`, `mood_flag`, `pain_or_injury_mentioned`, `possible_pr`).
- **Output:** One paragraph of 40-60 words; upserts `DailySummary` keyed on `date = startOfDay(today)` with the text + `keyStats`.
- **Trigger:** Second step of every nightly run.
- **`maxTokens`:** 180.
- **System prompt (verbatim, `MemoryMaintainer.swift:70-146`):**

```
You are writing the coach's private notes on one day — texture and
notable features, not a log readout.

Write 40-60 words. Lead with the most notable thing about the day.
If nothing is notable, say so ("quiet day, nothing to flag"). Weave
numbers in to support the characterization, not as the main content.

Write in the coach's voice. Direct, specific, no filler, no
exclamation points, no validation theater.

## The most common failure mode

A summary that lists events is failed output. If what you wrote
reads like "3 meals, X cal, Y protein, did exercise Z, HRV was N"
— that's a log, not a summary. Rewrite it.

## Examples

Input: User's first real training day after a 9-month break. Ate
1,200 cal (700 under target), 130g protein. Bench 3×5 at 50kg
(baseline, no prior session to compare). HRV 78, normal. No
unusual conversation content.

Good output:
"First real training day of the restart. Bench felt heavy at 50kg
for 3×5 — expected after 9 months off. Ate 1,200 cal and 130g
protein, well short of target but the system is getting running.
HRV 78, normal. No red flags."

Bad output (do not produce this):
"Monday: 3 meals (1,200 cal, 130g protein), bench press 3x5 at
50kg, HRV 78. Steady start to the week."

---

Input: User drank 4 beers Tuesday evening. Wednesday: HRV 24 (down
from baseline ~80). Skipped gym. Ate 2,650 cal (750 over target),
105g protein. Logged "feeling gross" in afternoon.

Good output:
"Rough one. Tuesday's drinks dropped HRV to 24, about a 70%
crash. Skipped the gym, which was the right call. Ate 2,650 cal
and 105g protein — over on calories, under on protein. Mentioned
feeling gross in the afternoon. Recovery day, not a failure day."

Bad output:
"Wednesday: skipped training. Ate 2,650 cal, 105g protein. HRV
was 24. User reported feeling unwell."

---

Input: Normal productive day. 3 meals hitting targets (1,950 cal,
158g protein). No training scheduled. HRV 82, sleep 7h 20m.
Conversation was routine meal logging.

Good output:
"Steady non-training day. Hit targets without effort — 1,950 cal,
158g protein. HRV 82, sleep fine. Nothing to flag."

Bad output:
"3 meals totaling 1,950 cal and 158g protein. No training. HRV
82, slept 7h 20m."

## How to use the input

The user message below contains the raw day plus a pre-computed
context block: deltas from target, baseline-relative flags
("high"/"low"/"normal"), training progression vs prior session of
the same exercise, and conversation flags extracted from the day's
messages. Use these to pick what's notable. Do not recompute.

## Output

Return only the 40-60 word summary. No headers, no labels, no
bullets, no prefatory text. Plain prose, one short paragraph.
```

### `updatePatterns()` — Level 1.5 patterns
- **File:** `Ledger/Services/MemoryMaintainer.swift:441-477`
- **Input:** 28 most recent `DailySummary` rows + all current `Pattern` rows, passed as `PatternPromptInput { summaries, currentPatterns }`. Skips entirely if there are no summaries.
- **Output:** JSON with `operations[]` where each operation is `add` / `update` / `remove`. The prompt requires a `wouldChangeCoachBehaviorBy` field on every add/update but the Swift decoder (`PatternOperation` in `MemoryMaintainer.swift:1765-1773`) does not include it — the model produces it but the code drops it. Decoded into `PatternMaintenanceResponse` and applied by `applyPatternOperations` (`MemoryMaintainer.swift:727-770`): removes delete, adds/updates upsert on `key`, defaulting missing `description` to the key, missing `confidence` to `.low`, and missing dates to `now()`.
- **Trigger:** Only runs inside the weekly branch of `runNightlySequence` — when it's Sunday or >7 days since last weekly pass.
- **`maxTokens`:** 700.
- **System prompt (verbatim, `MemoryMaintainer.swift:148-242`):**

```
Your job is to identify patterns that would change how the coach
responds to this person. Patterns that are real but useless are
noise. Don't produce noise.

## The utility test

For each candidate pattern, ask: would the coach's response to a
future message change if it knew this pattern? Name the specific
way it would change. If you can't name a specific way, the pattern
is not worth storing.

Patterns that pass the test:
- "Protein drops below 130g on days when Turkish food is logged"
  — coach can proactively suggest protein-forward sides when
  Turkish food comes up.
- "HRV crashes 60-70% the morning after 4+ drinks, recovers by
  day 2" — coach can predict tomorrow's HRV from tonight's
  drinks.
- "Bench progresses faster on heavy triples than on higher-volume
  work" — coach can adjust programming recommendations.

Patterns that FAIL the test (do NOT store):
- "User consistently logs meals in the morning" — doesn't change
  coach behavior.
- "User trains multiple times per week" — baseline behavior, not
  a pattern.
- "User has varied eating habits" — too generic to act on.

## Specificity test

Good patterns are specific enough that they couldn't describe a
random other user. "Omar's protein drops on Turkish food days" is
specific. "User eats breakfast" is not.

## Confidence calibration

- low: 3-5 observations. Pattern noticed but could be coincidence.
- medium: 6-10 observations. Clear pattern, few or no
  counter-examples.
- high: 10+ observations. Pattern is reliable across an extended
  period.

Default to low at 3 observations. Only promote when the evidence
genuinely merits it. It is better to keep a real pattern at low
confidence than to overclaim.

## Pattern persistence — the input carries both existing patterns and new summaries

You are receiving: (a) existing patterns from prior runs, under
`currentPatterns`, and (b) new observations from this window,
under `summaries`.

Update existing patterns:
- If new evidence reinforces an existing pattern, emit an `update`
  with an incremented observation count (reflected in
  `evidenceNote`) and potentially raised `confidence`. Set
  `lastReinforced` to the most recent supporting date.
- If new evidence contradicts an existing pattern, emit an
  `update` that lowers `confidence` and notes the contradiction,
  or `remove` it if contradictions dominate.
- If a pattern's `lastReinforced` is 8+ weeks before today and
  nothing in this window reinforces it, emit an `update` that
  lowers `confidence` one level — it may be stale.

Only create new patterns for genuinely new observations not
covered by existing patterns. Do not regenerate from scratch.

## Output format

Return JSON only. Exact shape:

{
  "operations": [
    {
      "action": "add" | "update" | "remove",
      "key": "short_snake_case_key",
      "description": "specific, falsifiable observation in one sentence",
      "evidenceNote": "quantitative evidence where possible — '6 of 7 days', 'mean X vs baseline Y'",
      "confidence": "low" | "medium" | "high",
      "firstObserved": "YYYY-MM-DD",
      "lastReinforced": "YYYY-MM-DD",
      "wouldChangeCoachBehaviorBy": "one sentence naming the specific way coach behavior would change"
    }
  ]
}

For remove operations, include only action, key, and evidenceNote.

If no patterns meet the utility bar this run, return:
{ "operations": [] }

It is a successful run to return zero operations. Do not invent
patterns to fill space.
```

### `proposeIdentityUpdates()` — Level 1 identity proposals
- **File:** `Ledger/Services/MemoryMaintainer.swift:479-517`
- **Input:** Current `IdentityProfile.markdownContent`, 28 most recent daily summaries, and current patterns, as `IdentityPromptInput { currentIdentityMarkdown, summaries, currentPatterns }`. Skips if no summaries.
- **Output:** JSON with `proposals[]`; decoded into `IdentityProposalResponse` and applied by `applyIdentityProposals` (`MemoryMaintainer.swift:772-822`). **Only proposals with `kind == .factual` AND `confidence == .high` are actually written to the profile** via `IdentityProfileDocument.upserting(key:value:into:)`. Other proposals are only logged via `Logger.info(...)` and not persisted anywhere — there is no proposal review queue model in the current code.
- **Trigger:** Weekly branch of `runNightlySequence`, runs after `updatePatterns`.
- **`maxTokens`:** 500.
- **System prompt (verbatim, `MemoryMaintainer.swift:244-305`):**

```
You review the week's conversations and summaries for identity
signal that the coach missed capturing in real time. Numerical
facts (weight, calories, training loads) should already be
captured on the fly. Your focus here is the quieter material:
framings, constraints, rule-outs, and changes in how the user
describes themselves.

## What to look for

- New framings: did the user describe their goal, situation, or
  approach in a new way this window? Capture their language, not
  a paraphrase. Key: `goal_framing`, `origin_story`, or
  `approach` depending on which.
- New constraints: did any dietary, medical, or practical limits
  emerge? Key: `constraint`.
- New rule-outs: did they try something and decide against it?
  Key: `ruled_out`.
- Changed framings: does the user now describe their goal
  differently than before? If so, emit a new `goal_framing`
  proposal with the updated language and a note in the rationale
  that this supersedes the prior framing.
- Missed atomic facts: only if the coach clearly failed to capture
  one in real time (e.g. user stated their age or height in
  conversation but no identity fact was stored for it).

## What NOT to propose

- Derived metrics the coach can compute from logs ("user trains
  strength", "user tracks calories daily"). These are behavior
  descriptions, not identity.
- Interpretive framings the user did not state themselves.
- Facts already present in the current identity profile.

## Confidence calibration

- high: the user stated it directly and unambiguously. Only `high`
  + `factual` proposals are written to the profile; everything
  else is logged but discarded. So be deliberate — mark as `high`
  only when you'd stake your reputation on it.
- medium: strong inference from multiple signals.
- low: weak inference or speculation.

## Output format

Return JSON only. Exact shape:

{
  "proposals": [
    {
      "kind": "factual" | "interpretive",
      "confidence": "low" | "medium" | "high",
      "key": "short_snake_case_key",
      "value": "the fact, framing, or constraint to store — may be multi-sentence for framings",
      "rationale": "brief evidence-based reason, citing the summary date or conversation turn"
    }
  ]
}

If nothing meets the bar, return { "proposals": [] }. Returning
zero proposals is a successful run.
```

### `rollupWeek()` — weekly archive
- **File:** `Ledger/Services/MemoryMaintainer.swift:519-564`
- **Input:** All `DailySummary` rows. Groups by start-of-ISO-week. For each week whose `interval.end <= now - 28 days`, calls `archiveRollupText(scope: "week", …)` with the daily entries (date, summaryText, keyStats).
- **Output:** One-paragraph summary; upserts `WeeklySummary(startDate, endDate, summaryText, keyStats: aggregate(...))` and **deletes the source `DailySummary` rows**.
- **Trigger:** Nightly, after the optional weekly branch.
- **`maxTokens`:** 260.

### `rollupMonth()` — monthly archive
- **File:** `Ledger/Services/MemoryMaintainer.swift:566-612`
- **Input:** All `WeeklySummary` rows ending before the start of the current calendar month. Groups by start-of-month. For each eligible month, calls `archiveRollupText(scope: "month", …)` with the weekly entries.
- **Output:** One-paragraph summary; upserts `MonthlySummary(startDate, endDate, summaryText, keyStats)` and **deletes the source `WeeklySummary` rows**.
- **Trigger:** Nightly, after `rollupWeek`.
- **`maxTokens`:** 260.

### `archiveRollupText` (shared helper, both rollups)
Helper method at `MemoryMaintainer.swift:618-637`. System prompt (verbatim, `MemoryMaintainer.swift:307-319`):

```
You compress older Ledger memory into archive summaries.

Your job:
- Turn the supplied daily or weekly entries into one paragraph for archive recall.
- Preserve the main themes, concrete events, and overall direction of the period.
- Stay grounded in the provided entries and aggregate stats.

Output rules:
- Return a single paragraph only.
- No headings, bullets, or preamble.
- No invented facts.
```

### `preGenerateMorningStandup()` — **stub**
- **File:** `Ledger/Services/MemoryMaintainer.swift:614-616`
- Body: `logger.debug("Morning standup generation is still a stub.")`. No LLM call, no write. Runs at the end of every nightly sequence.

### Orchestration (`MemoryMaintenanceCoordinator.runNightlySequence`)
File: `Ledger/Services/MemoryMaintenanceScheduler.swift:32-87`. Order of operations per run:

1. `updateActiveState`
2. `summarizeToday`
3. If `shouldRunWeekly`: `updatePatterns`, then `proposeIdentityUpdates`, then persist weekly timestamp to `UserDefaults`.
4. `rollupWeek`
5. `rollupMonth`
6. `preGenerateMorningStandup` (stub)
7. Persist nightly timestamp to `UserDefaults`.

If any step throws, the whole run aborts, the nightly timestamp is not written, and the method returns `false`. Cancellation (`Task.checkCancellation`) is checked between steps.

## 6. Tool calls from the coach

Defined in `Ledger/Services/CoachTools.swift`. Executed in `ChatViewModel.persistToolUse` (`ChatViewModel.swift:166-226`). Every tool has `eagerInputStreaming: true`. Validation is limited to JSON decoding into typed Swift payloads and the `enum` constraint on the metric type in the tool schema.

### `update_meal_log`
- **Description:** "Log a meal or food the user mentioned eating. Call this every time the user mentions eating something, even casually."
- **Schema** (`CoachTools.swift:20-43`):
  - `description: string` — required
  - `estimated_calories: integer` — required
  - `estimated_protein_grams: integer` — required
- **Writes to:** `StoredMeal` (`ChatViewModel.swift:175-186`). Date = `now()`. Returns `"Meal logged."`.

### `record_workout_set`
- **Description:** "Record one or more sets of an exercise the user mentioned training."
- **Schema** (`CoachTools.swift:44-69`):
  - `exercise: string` — required
  - `summary: string` — required
  - `notes: string` — optional
- **Writes to:** `StoredWorkoutSet`. Date = `now()`. Returns `"Workout logged."`.

### `update_metric`
- **Description:** "Record a body/recovery metric the user shared."
- **Schema** (`CoachTools.swift:70-101`):
  - `type: string` — required, `enum: ["hrv", "sleep", "weight", "mood", "other"]`
  - `value: string` — required
  - `context: string` — optional
- **Writes to:** `StoredMetric`. Date = `now()`. Returns `"Metric logged."`.

### `update_identity_fact`
- **Description:** "Persist something about this person's identity — not just numeric facts but the way they frame their goal, the constraints they operate under, the approaches they've tried. Use this whenever you learn something that would change how you'd respond to them in the future." The schema description explicitly enumerates supported key categories: atomic facts (`name`, `age`, `height`, `current_weight`, `goal_weight`, `calorie_target`, `protein_target`, `goal_start_date`), framings where values can be multi-sentence (`goal_framing`, `origin_story`, `approach`), and `constraint` / `ruled_out` / `preference`. The description instructs the model to preserve the user's own language for framings rather than paraphrasing.
- **Schema** (`CoachTools.swift:102-125`):
  - `key: string` — required
  - `value: string` — required (may be multi-sentence for framings/constraints/rule-outs)
- **Writes to:** `IdentityProfile.markdownContent` via `IdentityProfileDocument.upserting` (`ChatViewModel.upsertProfileEntry`, `ChatViewModel.swift:229-259`). Creates the singleton row if absent. Key/value get bucketed into sections by `IdentityProfileDocument.section(forKey:)` keyword matching. Returns `"Identity fact stored."`. Handled in `ChatViewModel.persistToolUse` under the case `"update_identity_fact"` (`ChatViewModel.swift:212-215`); the payload struct (`UpdateProfilePayload`) still carries its legacy name but decodes the same `{ key, value }` shape.

### `search_archive`
- **Description:** "Search older weekly and monthly summaries when the user asks about historical periods that are no longer in the loaded context."
- **Schema** (`CoachTools.swift:124-140`):
  - `query: string` — required
- **Reads from:** `WeeklySummary`, `MonthlySummary`. Implemented by `ContextBuilder.archiveSearchMarkdown(query:)` calling `archiveMatches` — substring match against `summaryText.lowercased()`, top 3 results ordered by `startDate` desc. See §8.

### Guardrails
Beyond JSON decoding and the metric `enum`, there are no server-side guardrails — no rate limits, bounds checks, deduplication, or size limits on any field. Failures in decoding surface as tool-error results back to the model (`ChatViewModel.swift:156-163`).

## 7. Background scheduling

File: `Ledger/Services/MemoryMaintenanceScheduler.swift`.

### What uses `BGTaskScheduler`
`SystemBackgroundTaskScheduler` (`MemoryMaintenanceScheduler.swift:142-169`) wraps `BGTaskScheduler.shared`. `MemoryMaintenanceScheduler` registers a single `BGProcessingTask` with identifier `"com.omarelamin.ledger.memory-maintenance"`. Registration happens once, from `LedgerApp.init` (`LedgerApp.swift:10-12`), guarded by `appEnvironment.shouldRegisterBackgroundTasks` which is false in UI test / hosted unit test environments.

### Conditions that trigger the nightly run
The submitted `BGProcessingTaskRequest` sets:
- `requiresExternalPower = true`
- `requiresNetworkConnectivity = true`
- `earliestBeginDate = nextScheduledRun(after: now)`

`nextScheduledRun` (`MemoryMaintenanceScheduler.swift:267-281`) picks today at 03:15 local, or tomorrow at 03:15 if today's 03:15 has already passed. Re-scheduling happens:
- After registration (`registerBackgroundTasks`).
- When the scene becomes `.active` (`handleScenePhaseChange`).
- At the start of handling a fired background task (`handleBackgroundTask`).
- In the expiration handler.

### What happens if a run is missed
Missed runs are not retried specifically. Next opportunity is the next scheduled `BGProcessingTask` or the next scene-phase-active event.

### Fallback behavior on app foreground
`handleScenePhaseChange(.active)` (`MemoryMaintenanceScheduler.swift:240-250`) re-submits `scheduleNextRun()` and launches `coordinator.runNightlySequence(force: false, trigger: "foreground")`. `force: false` means `runNightlySequence` first checks `shouldRunNightly(at:)` — returns `true` only if there is no previous successful nightly timestamp OR `now - lastRun > 36 hours`. So a cold app launch after a gap of >36h will kick off a nightly pass in-foreground.

Additionally, `isRunning` (actor-isolated) prevents concurrent runs, and if no API key is configured (`hasAPIKeyConfigured == false`) the run is skipped successfully. `LedgerAppEnvironment.shouldAutoRunMaintenance` gates both the scene-phase foreground call and `registerBackgroundTasks`; it is false in UI tests and hosted unit tests unless `LEDGER_TEST_AUTO_MAINTENANCE=1`.

### `UserDefaults` keys
- `ledger.memory.lastSuccessfulNightlyRunAt` — set at the end of a successful full run.
- `ledger.memory.lastSuccessfulWeeklyMaintenanceAt` — set when the weekly branch (patterns + identity proposals) has completed successfully.

Both are scoped to the process's `UserDefaults`, which in production is `.standard` but is swapped for isolated suites under UI tests and hosted unit tests.

## 8. Archive and retrieval

### How older data is compressed
Two-stage rollup, both running nightly:

1. **Daily → Weekly** (`rollupWeek`). When a full ISO week ended more than 28 days before today, all that week's `DailySummary` rows are sent to the archive roll-up prompt and replaced by a single `WeeklySummary` row. The source dailies are deleted in the same `ModelContext.save`.
2. **Weekly → Monthly** (`rollupMonth`). Any `WeeklySummary` whose `endDate` is before the start of the current calendar month is grouped by month; groups become a `MonthlySummary` and the source weeklies are deleted.

`SummaryKeyStats` are aggregated by `MemoryMaintainer.aggregate(_:)` (`MemoryMaintainer.swift:982-998`): `calories` and `protein` become means (rounded), `trained` is ORed, `hrv` and `sleep` take the last non-nil value.

### Archive search
Implemented by the coach's `search_archive` tool. Server-side logic lives in `ContextBuilder.archiveMatches(query:)` and `archiveSearchMarkdown(query:)` (`ContextBuilder.swift:140-198`).

- **Mechanism:** Plain substring match. `query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()` is checked against `summaryText.lowercased()` via `String.contains`. No embeddings, no tokenization, no ranking other than `startDate` desc, no fuzzy matching, no stemming.
- **Sources:** `WeeklySummary` + `MonthlySummary` (not `DailySummary` — dailies in the recent 28-day window are already in-context; older ones have been compressed away).
- **Output:** Top 3 matches combined into a markdown list like `- Week Apr 1–Apr 7: <summaryText>`. Empty results → `"No archive matches for \"<query>\"."`.

## 9. Known gaps and TODOs

### Explicit TODO/FIXME comments (grep of `Ledger/**/*.swift`)
- `Ledger/Services/MemoryMaintainer.swift:65-68` — `// TODO: generate WeeklySummary narrative text for History week blocks; replace MockHistoryNarratives wired into HistoryView once this lands. Plumbs into HistoryWeekSection.narrative via the builder's narrativeProvider closure.`
- `Ledger/Services/MemoryMaintainer.swift:615` — `logger.debug("Morning standup generation is still a stub.")` (the method body is effectively a TODO — it's called nightly but does nothing).

No other `TODO`/`FIXME`/`XXX` markers were found in the Swift sources.

### Other gaps worth flagging
- **`HistoryView` narratives are mock data.** `HistoryView.weeks` (`Ledger/Views/HistoryView.swift:14-43`) calls `MockHistoryNarratives.narrative(forWeekStartingOn:anchorDate:)` (`Ledger/MockData/MockHistory.swift`), not `WeeklySummary.summaryText`. There are fixed strings for "this week / last week / week before" and a `justGettingStarted` fallback. Wiring up real weekly narratives is the TODO above.
- **Identity proposals with confidence < high are silently discarded.** `applyIdentityProposals` (`MemoryMaintainer.swift:772-822`) only writes `.factual` + `.high`; other proposals are `logger.info(...)` entries. There is no `IdentityProposal` persisted model and no review UI.
- **`wouldChangeCoachBehaviorBy` is discarded on the Swift side.** The patterns prompt instructs the model to return `wouldChangeCoachBehaviorBy` on every add/update operation as the output of the utility test, but `PatternOperation` (`MemoryMaintainer.swift:1765-1773`) does not decode the field. The model produces it, the code drops it. If we want to persist or display the stated behavioral change, the struct and the `Pattern` model need a field added.
- **`archiveRollupSystemPrompt` was not rewritten in the maintainer-voice pass.** It's still the terse 4-rule prompt that asks for "one paragraph for archive recall" (`MemoryMaintainer.swift:307-319`). Archive summaries will therefore read in the old mechanical register even after daily summaries shift into the new coach-voice register. If we want archive entries to feel like the rest of the memory system, this prompt also needs the same treatment.
- **Archive search is pure substring.** A query of `"drinking"` will not match a summary that says `"drinks"`; a query of `"travel week"` will not match `"trip"`.
- **No vector store, no embeddings, no retrieval scoring anywhere.** All "retrieval" is deterministic SQL queries or the substring match above.
- **`searchArchive` never searches `DailySummary`.** A user asking about a day 20 days ago will get that day's summary as part of the always-loaded "Recent days" section, but `search_archive` itself never queries `DailySummary`.
- **Working-weight parsing is regex over `summary` strings.** `MemoryMaintainer.parseLoadText` (`MemoryMaintainer.swift:1519-1551`) handles `@ NNkg`, `NNkg ×`, and bodyweight `bw`; other summary formats won't contribute a working weight to the active-state snapshot.
- **Background task identifier must be registered in the app's `Info.plist` / `BGTaskSchedulerPermittedIdentifiers`**; I did not verify the Info.plist — worth confirming that `com.omarelamin.ledger.memory-maintenance` is listed.
- **Specced in earlier sessions but not in the current tree:** the "morning standup" artifact (there is no `MorningStandup` @Model, no pre-generated copy surface, only the stub method). If an earlier session specced a dedicated model or UI for it, the current code has only the placeholder method.

## 10. File map

Swift files involved in the memory system:

- `Ledger/LedgerApp.swift` — App entry point; constructs `LedgerAppEnvironment`, registers background tasks.
- `Ledger/LedgerAppEnvironment.swift` — Wires `ModelContainer`, `MemoryMaintainer`, `MemoryMaintenanceCoordinator`, `MemoryMaintenanceScheduler`; chooses scripted vs real clients based on launch-environment flags; owns `LedgerLaunchConfiguration` (test-mode detection, fixed clock, isolated `UserDefaults`).
- `Ledger/ContentView.swift` — Hosts the tab view and forwards scene-phase changes to `MemoryMaintenanceScheduler.handleScenePhaseChange`; also renders `LedgerTestHarnessControls` (UI affordances to set time, advance days, force nightly, dump snapshot).
- `Ledger/Models/Persistence.swift` — All `@Model` definitions for legacy, V1, V2 schemas; typealiases selecting V2; `IdentityProfileDocument` markdown helpers; `SummaryKeyStats`; `PatternConfidence`.
- `Ledger/Models/LedgerPersistentModels.swift` — `ModelContainer` factories, `SchemaMigrationPlan`, legacy store recovery (including raw-SQLite inspection in `looksLikeLegacyStore`).
- `Ledger/Models/Message.swift` — In-memory `Message` struct and `MessageRole` enum used by the chat view.
- `Ledger/Models/HistoryTimeline.swift` — `HistoryWeekSection`, `HistoryDaySnapshot`, `LogTextFormatter` (used by `ContextBuilder.todayMarkdown`), `HistoryTimelineBuilder`.
- `Ledger/MockData/MockHistory.swift` — `MockHistoryNarratives` static strings currently used in place of real `WeeklySummary` narratives in `HistoryView`.
- `Ledger/Services/ContextBuilder.swift` — Assembles the chat context block; exposes `structuredData`, `dateRangeMessages`, `recentDailySummaries`, `mediumOrHighPatterns`, `archiveMatches`, `archiveSearchMarkdown`.
- `Ledger/Services/CoachPrompt.swift` — Coach system prompt string; single entry point `systemPrompt(contextBlock:)` that inlines the memory block.
- `Ledger/Services/CoachTools.swift` — Static `CoachTools.all` list of tool declarations shipped to the Anthropic API.
- `Ledger/Services/CoachStreamingClient.swift` — `CoachStreamingClient` protocol consumed by `ChatViewModel`.
- `Ledger/Services/ClaudeClient.swift` — Anthropic API client implementing both `CoachStreamingClient` (streaming coach) and `MemoryTextGeneratingClient` (non-streaming generate-text for maintainer prompts); SSE parsing types.
- `Ledger/Services/ClaudeStreamProcessor.swift` — SSE event processor used by `ClaudeClient.streamTurn` (not read in detail for this doc).
- `Ledger/Services/MemoryMaintainer.swift` — All five LLM-driven maintainer methods, prompt input structs, upsert helpers, streak computation, working-weight regex parsing, archive rollup helper.
- `Ledger/Services/MemoryMaintenanceScheduler.swift` — `MemoryMaintenanceCoordinator` (orchestrates the nightly sequence), `BackgroundTaskScheduling` + `SystemBackgroundTaskScheduler` wrappers around `BGTaskScheduler`, `DisabledMemoryTextGenerator`, `MemoryMaintenanceScheduler` (registration + scene-phase + scheduling math).
- `Ledger/Services/LedgerTestSupport.swift` — `LedgerTestClock`, `LedgerTestHarness` (time control + `MemorySnapshot.capture`), `MemorySnapshot` + value-type equivalents used for test assertions, `ScriptedMemoryTextGenerator` producing deterministic outputs that mirror each maintainer prompt.
- `Ledger/ViewModels/ChatViewModel.swift` — Sends chat, builds context block via `ContextBuilder`, parses streamed tool calls, persists tool results into the relevant SwiftData models, handles `search_archive` by delegating to `ContextBuilder.archiveSearchMarkdown`.
- `Ledger/Views/HistoryView.swift` — Consumes `HistoryTimelineBuilder` and, today, `MockHistoryNarratives` for weekly narrative copy.
