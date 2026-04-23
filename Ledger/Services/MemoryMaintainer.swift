import Foundation
import OSLog
import SwiftData

actor MemoryMaintainer {
    static let activeStateSystemPrompt = """
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

    ## Example when no name is on file

    "3 weeks into a cut from 83kg toward 75kg, rebuilding training
    after a 9-month break. Current 7-day average 82.6kg — down 0.4kg
    from last week, on track. Eating averages 1,850 cal and 138g
    protein, both slightly under targets. Bench at 50kg for 3×5,
    target 85kg. HRV baseline still forming, only 5 days of data."

    No subject needed. The coach knows who this is.

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

    The person's name, if known, is in `preComputedContext.goalFrame.name`.
    If that field is null, do not write any name. Refer to them as "they"
    or "the user," or omit the subject entirely where the prose flows
    without it ("3 weeks into a cut..." rather than "Chris is 3 weeks
    into a cut..."). Never write a name you did not receive. Fabricating
    a name corrupts the situational brief the coach reads on every turn.

    ## Dating events in prose

    When your prose references a specific dated event — a workout, a weight
    reading, an HRV crash, a conversation day — use the absolute date
    ("Apr 20") or window-relative phrasing ("over the past week," "this
    week's training"). Do not use "yesterday," "two days ago," "last
    Tuesday," or other anchors that decay. This snapshot may be read a day
    or more after it was generated; relative anchors drift.

    ## Output

    Return only the brief prose. No headers, no labels, no preamble.
    """

    // TODO: generate WeeklySummary narrative text for History week blocks;
    // replace MockHistoryNarratives wired into HistoryView once this lands.
    // Plumbs into HistoryWeekSection.narrative via the builder's
    // narrativeProvider closure.

    static let dailySummarySystemPrompt = """
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
    """

    static let patternsSystemPrompt = """
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
    random other user. "Protein drops below 130g on Turkish food days"
    is specific. "User eats breakfast" is not.

    Pattern descriptions must not include the user's name. Patterns
    are behavioral, not personal.

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
    """

    static let identityUpdateSystemPrompt = """
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
    """

    static let archiveRollupSystemPrompt = """
    You compress older Ledger memory into archive summaries.

    Your job:
    - Turn the supplied daily or weekly entries into one paragraph for archive recall.
    - Preserve the main themes, concrete events, and overall direction of the period.
    - Stay grounded in the provided entries and aggregate stats.

    Output rules:
    - Return a single paragraph only.
    - No headings, bullets, or preamble.
    - No invented facts.
    """

    private let modelContainer: ModelContainer
    private let textGenerator: any MemoryTextGeneratingClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.omarelamin.ledger", category: "MemoryMaintainer")

    init(
        modelContainer: ModelContainer,
        textGenerator: any MemoryTextGeneratingClient,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContainer = modelContainer
        self.textGenerator = textGenerator
        self.calendar = calendar
        self.now = now
    }

    func updateActiveState() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let today = now()
        let todayBounds = builder.dayBounds(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -7, to: todayBounds.start) ?? todayBounds.start
        let windowEnd = todayBounds.end

        let windowData = try builder.structuredData(start: windowStart, end: windowEnd)
        let dailyStats = try dailyStats(from: builder, start: windowStart, through: todayBounds.start)
        let todayMarkdown = builder.todayMarkdown()

        let extendedStart = calendar.date(byAdding: .day, value: -28, to: todayBounds.start) ?? windowStart
        let extendedMetrics = try builder.structuredData(start: extendedStart, end: todayBounds.end).metrics
        let profile = try fetchIdentityProfile(in: context)
        let identityFacts = IdentityProfileDocument.facts(from: profile?.markdownContent ?? "")
        let enrichment = computeActiveStateEnrichment(
            identityFacts: identityFacts,
            dailyStats: dailyStats,
            extendedMetrics: extendedMetrics,
            today: todayBounds.start
        )

        let input = ActiveStatePromptInput(
            windowStart: Self.dayString(windowStart),
            windowEnd: Self.dayString(todayBounds.start),
            todayMarkdown: todayMarkdown,
            dailyStats: dailyStats,
            latestMetrics: latestMetricSnapshots(from: windowData.metrics),
            trainingStreakDays: streakLength(in: dailyStats, keyPath: \.trained),
            loggingStreakDays: loggingStreakLength(in: dailyStats),
            workingWeights: latestWorkingWeights(from: windowData.workoutSets),
            preComputedContext: enrichment
        )

        let markdown = try await textGenerator.generateText(
            systemPrompt: Self.activeStateSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 700
        )

        try upsertActiveStateSnapshot(
            markdown: markdown,
            generatedAt: today,
            in: context
        )
    }

    func summarizeToday() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let today = now()
        let bounds = builder.dayBounds(for: today)
        let structured = try builder.structuredData(start: bounds.start, end: bounds.end)
        let messages = try builder.dateRangeMessages(start: bounds.start, end: bounds.end)

        let profile = try fetchIdentityProfile(in: context)
        let identityFacts = IdentityProfileDocument.facts(from: profile?.markdownContent ?? "")

        let baselineStart = calendar.date(byAdding: .day, value: -7, to: bounds.start) ?? bounds.start
        let baselineStats = try dailyStats(from: builder, start: baselineStart, through: bounds.start)
            .filter { $0.date != Self.dayString(bounds.start) }
        let priorWorkoutsStart = calendar.date(byAdding: .day, value: -90, to: bounds.start) ?? bounds.start
        let priorWorkouts = try builder.structuredData(start: priorWorkoutsStart, end: bounds.start).workoutSets
        let priorHRVMetrics = try builder.structuredData(start: priorWorkoutsStart, end: bounds.start).metrics

        let enrichment = computeDailyEnrichment(
            identityFacts: identityFacts,
            today: structured,
            todayMessages: messages.map {
                ConversationSnippet(
                    role: $0.role,
                    content: $0.content,
                    date: Self.timestampString($0.timestamp)
                )
            },
            baselineStats: baselineStats,
            priorWorkouts: priorWorkouts,
            priorMetrics: priorHRVMetrics
        )

        let input = DailySummaryPromptInput(
            date: Self.dayString(bounds.start),
            keyStats: structured.keyStats,
            todayMarkdown: builder.todayMarkdown(),
            messages: messages.map {
                ConversationSnippet(
                    role: $0.role,
                    content: $0.content,
                    date: Self.timestampString($0.timestamp)
                )
            },
            preComputedContext: enrichment
        )

        let summaryText = try await textGenerator.generateText(
            systemPrompt: Self.dailySummarySystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 180
        )

        try upsertDailySummary(
            date: bounds.start,
            summaryText: summaryText,
            keyStats: structured.keyStats,
            in: context
        )
    }

    func updatePatterns() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let summaries = try builder.recentDailySummaries(limit: 28)
        guard !summaries.isEmpty else {
            return
        }

        let patterns = try fetchPatterns(in: context)
        let input = PatternPromptInput(
            summaries: summaries.map {
                SummarySnapshot(
                    date: Self.dayString($0.date),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            },
            currentPatterns: patterns.map {
                PatternSnapshot(
                    key: $0.key,
                    description: $0.descriptionText,
                    evidenceNote: $0.evidenceNote,
                    confidence: $0.confidence,
                    firstObserved: Self.dayString($0.firstObserved),
                    lastReinforced: Self.dayString($0.lastReinforced)
                )
            }
        )

        let responseText = try await textGenerator.generateText(
            systemPrompt: Self.patternsSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 1200
        )
        let response = try decodeJSON(PatternMaintenanceResponse.self, from: responseText)
        try applyPatternOperations(response.operations, in: context)
    }

    func proposeIdentityUpdates() async throws {
        let context = ModelContext(modelContainer)
        let builder = ContextBuilder(modelContext: context, calendar: calendar, now: now)
        let summaries = try builder.recentDailySummaries(limit: 28)
        guard !summaries.isEmpty else {
            return
        }

        let currentProfile = try fetchIdentityProfile(in: context)
        let patterns = try fetchPatterns(in: context)
        let input = IdentityPromptInput(
            currentIdentityMarkdown: currentProfile?.markdownContent ?? "",
            summaries: summaries.map {
                SummarySnapshot(
                    date: Self.dayString($0.date),
                    summaryText: $0.summaryText,
                    keyStats: $0.keyStats
                )
            },
            currentPatterns: patterns.map {
                PatternSnapshot(
                    key: $0.key,
                    description: $0.descriptionText,
                    evidenceNote: $0.evidenceNote,
                    confidence: $0.confidence,
                    firstObserved: Self.dayString($0.firstObserved),
                    lastReinforced: Self.dayString($0.lastReinforced)
                )
            }
        )

        let responseText = try await textGenerator.generateText(
            systemPrompt: Self.identityUpdateSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 900
        )
        let response = try decodeJSON(IdentityProposalResponse.self, from: responseText)
        try applyIdentityProposals(response.proposals, in: context)
    }

    func rollupWeek() async throws {
        let context = ModelContext(modelContainer)
        let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now())) ?? now()
        let summaries = try context.fetch(
            FetchDescriptor<DailySummary>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        )

        let grouped = Dictionary(grouping: summaries) { summary in
            startOfWeek(for: summary.date)
        }

        for startDate in grouped.keys.sorted() {
            guard
                let interval = calendar.dateInterval(of: .weekOfYear, for: startDate),
                interval.end <= cutoff,
                let items = grouped[startDate]
            else {
                continue
            }

            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? startDate
            let summaryText = try await archiveRollupText(
                scope: "week",
                startDate: startDate,
                endDate: endDate,
                entries: items.map {
                    RollupEntrySnapshot(
                        date: Self.dayString($0.date),
                        summaryText: $0.summaryText,
                        keyStats: $0.keyStats
                    )
                }
            )

            try upsertWeeklySummary(
                startDate: startDate,
                endDate: endDate,
                summaryText: summaryText,
                keyStats: aggregate(items.map(\.keyStats)),
                sourceEntries: items,
                in: context
            )
        }
    }

    func rollupMonth() async throws {
        let context = ModelContext(modelContainer)
        let startOfCurrentMonth = calendar.dateInterval(of: .month, for: now())?.start ?? calendar.startOfDay(for: now())
        let summaries = try context.fetch(
            FetchDescriptor<WeeklySummary>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        )

        let eligible = summaries.filter { $0.endDate < startOfCurrentMonth }
        let grouped = Dictionary(grouping: eligible) { summary in
            startOfMonth(for: summary.startDate)
        }

        for startDate in grouped.keys.sorted() {
            guard
                let interval = calendar.dateInterval(of: .month, for: startDate),
                interval.end <= startOfCurrentMonth,
                let items = grouped[startDate]
            else {
                continue
            }

            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? startDate
            let summaryText = try await archiveRollupText(
                scope: "month",
                startDate: startDate,
                endDate: endDate,
                entries: items.map {
                    RollupEntrySnapshot(
                        date: "\(Self.dayString($0.startDate)) → \(Self.dayString($0.endDate))",
                        summaryText: $0.summaryText,
                        keyStats: $0.keyStats
                    )
                }
            )

            try upsertMonthlySummary(
                startDate: startDate,
                endDate: endDate,
                summaryText: summaryText,
                keyStats: aggregate(items.map(\.keyStats)),
                sourceEntries: items,
                in: context
            )
        }
    }

    func preGenerateMorningStandup() async {
        logger.debug("Morning standup generation is still a stub.")
    }

    private func archiveRollupText(
        scope: String,
        startDate: Date,
        endDate: Date,
        entries: [RollupEntrySnapshot]
    ) async throws -> String {
        let input = RollupPromptInput(
            scope: scope,
            startDate: Self.dayString(startDate),
            endDate: Self.dayString(endDate),
            aggregateStats: aggregate(entries.map(\.keyStats)),
            entries: entries
        )

        return try await textGenerator.generateText(
            systemPrompt: Self.archiveRollupSystemPrompt,
            userPrompt: try encodePrompt(input),
            maxTokens: 260
        )
    }

    private func dailyStats(
        from builder: ContextBuilder,
        start: Date,
        through todayStart: Date
    ) throws -> [DailyStatSnapshot] {
        let dayCount = calendar.dateComponents([.day], from: start, to: todayStart).day ?? 0
        return try (0 ... max(dayCount, 0)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            let bounds = builder.dayBounds(for: day)
            let structured = try builder.structuredData(start: bounds.start, end: bounds.end)
            return DailyStatSnapshot(
                date: Self.dayString(bounds.start),
                calories: structured.keyStats.calories,
                protein: structured.keyStats.protein,
                trained: structured.keyStats.trained,
                hrv: structured.keyStats.hrv,
                sleep: structured.keyStats.sleep,
                loggedAnything: !structured.meals.isEmpty || !structured.workoutSets.isEmpty || !structured.metrics.isEmpty
            )
        }
    }

    private func latestMetricSnapshots(from metrics: [StoredMetric]) -> [MetricSnapshot] {
        let grouped = Dictionary(grouping: metrics) { $0.type.lowercased() }
        return grouped.keys.sorted().compactMap { key in
            guard let latest = grouped[key]?.max(by: { $0.date < $1.date }) else {
                return nil
            }
            return MetricSnapshot(
                type: latest.type,
                value: latest.value,
                context: latest.context,
                observedAt: Self.timestampString(latest.date)
            )
        }
    }

    private func latestWorkingWeights(from sets: [StoredWorkoutSet]) -> [WorkingWeightSnapshot] {
        let sortedSets = sets.sorted { $0.date > $1.date }
        var latestByExercise: [String: WorkingWeightSnapshot] = [:]

        for set in sortedSets {
            guard latestByExercise[set.exercise] == nil else {
                continue
            }

            guard let loadText = Self.parseLoadText(from: set.summary) else {
                continue
            }

            latestByExercise[set.exercise] = WorkingWeightSnapshot(
                exercise: set.exercise,
                loadText: loadText,
                observedAt: Self.timestampString(set.date),
                summary: set.summary
            )
        }

        return latestByExercise.values.sorted { $0.exercise < $1.exercise }
    }

    private func streakLength(
        in dailyStats: [DailyStatSnapshot],
        keyPath: KeyPath<DailyStatSnapshot, Bool>
    ) -> Int {
        var streak = 0
        for day in dailyStats.reversed() {
            guard day[keyPath: keyPath] else {
                break
            }
            streak += 1
        }
        return streak
    }

    private func loggingStreakLength(in dailyStats: [DailyStatSnapshot]) -> Int {
        var streak = 0
        for day in dailyStats.reversed() {
            guard day.loggedAnything else {
                break
            }
            streak += 1
        }
        return streak
    }

    private func applyPatternOperations(
        _ operations: [PatternOperation],
        in context: ModelContext
    ) throws {
        guard !operations.isEmpty else {
            return
        }

        let existingPatterns = try fetchPatterns(in: context)
        var patternsByKey = Dictionary(uniqueKeysWithValues: existingPatterns.map { ($0.key, $0) })

        for operation in operations {
            switch operation.action {
            case .remove:
                if let existing = patternsByKey.removeValue(forKey: operation.key) {
                    context.delete(existing)
                }
            case .add, .update:
                let firstObserved = operation.firstObserved ?? now()
                let lastReinforced = operation.lastReinforced ?? now()

                if let existing = patternsByKey[operation.key] {
                    existing.descriptionText = operation.description ?? existing.descriptionText
                    existing.evidenceNote = operation.evidenceNote
                    existing.confidence = operation.confidence ?? existing.confidence
                    existing.firstObserved = firstObserved
                    existing.lastReinforced = lastReinforced
                } else {
                    let pattern = Pattern(
                        key: operation.key,
                        descriptionText: operation.description ?? operation.key,
                        evidenceNote: operation.evidenceNote,
                        confidence: operation.confidence ?? .low,
                        firstObserved: firstObserved,
                        lastReinforced: lastReinforced
                    )
                    patternsByKey[operation.key] = pattern
                    context.insert(pattern)
                }
            }
        }

        try context.save()
    }

    private func applyIdentityProposals(
        _ proposals: [IdentityProposal],
        in context: ModelContext
    ) throws {
        guard !proposals.isEmpty else {
            return
        }

        let now = now()
        let profile = try fetchIdentityProfile(in: context)
        var markdown = profile?.markdownContent ?? ""
        var didApply = false

        for proposal in proposals {
            guard !proposal.key.isEmpty, !proposal.value.isEmpty else {
                continue
            }

            if proposal.kind == .factual, proposal.confidence == .high {
                markdown = IdentityProfileDocument.upserting(
                    key: proposal.key,
                    value: proposal.value,
                    into: markdown
                )
                didApply = true
            } else {
                logger.info(
                    "Queued identity proposal kind=\(proposal.kind.rawValue, privacy: .public) confidence=\(proposal.confidence.rawValue, privacy: .public) key=\(proposal.key, privacy: .public) rationale=\(proposal.rationale, privacy: .public)"
                )
            }
        }

        guard didApply else {
            return
        }

        if let profile {
            profile.markdownContent = markdown
            profile.lastUpdated = now
        } else {
            context.insert(
                IdentityProfile(
                    scope: IdentityProfile.defaultScope,
                    markdownContent: markdown,
                    lastUpdated: now
                )
            )
        }

        try context.save()
    }

    private func upsertActiveStateSnapshot(
        markdown: String,
        generatedAt: Date,
        in context: ModelContext
    ) throws {
        if let existing = try fetchActiveStateSnapshot(in: context) {
            existing.markdownContent = markdown
            existing.generatedAt = generatedAt
        } else {
            context.insert(
                ActiveStateSnapshot(
                    scope: ActiveStateSnapshot.defaultScope,
                    markdownContent: markdown,
                    generatedAt: generatedAt
                )
            )
        }

        try context.save()
    }

    private func upsertDailySummary(
        date: Date,
        summaryText: String,
        keyStats: SummaryKeyStats,
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { summary in
                summary.date == date
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.summaryText = summaryText
            existing.keyStats = keyStats
            existing.createdAt = now()
        } else {
            context.insert(
                DailySummary(
                    date: date,
                    summaryText: summaryText,
                    keyStats: keyStats,
                    createdAt: now()
                )
            )
        }

        try context.save()
    }

    private func upsertWeeklySummary(
        startDate: Date,
        endDate: Date,
        summaryText: String,
        keyStats: SummaryKeyStats,
        sourceEntries: [DailySummary],
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<WeeklySummary>(
            predicate: #Predicate { summary in
                summary.startDate == startDate
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.endDate = endDate
            existing.summaryText = summaryText
            existing.keyStats = keyStats
            existing.createdAt = now()
        } else {
            context.insert(
                WeeklySummary(
                    startDate: startDate,
                    endDate: endDate,
                    summaryText: summaryText,
                    keyStats: keyStats,
                    createdAt: now()
                )
            )
        }

        for entry in sourceEntries {
            context.delete(entry)
        }

        try context.save()
    }

    private func upsertMonthlySummary(
        startDate: Date,
        endDate: Date,
        summaryText: String,
        keyStats: SummaryKeyStats,
        sourceEntries: [WeeklySummary],
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<MonthlySummary>(
            predicate: #Predicate { summary in
                summary.startDate == startDate
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.endDate = endDate
            existing.summaryText = summaryText
            existing.keyStats = keyStats
            existing.createdAt = now()
        } else {
            context.insert(
                MonthlySummary(
                    startDate: startDate,
                    endDate: endDate,
                    summaryText: summaryText,
                    keyStats: keyStats,
                    createdAt: now()
                )
            )
        }

        for entry in sourceEntries {
            context.delete(entry)
        }

        try context.save()
    }

    private func fetchIdentityProfile(in context: ModelContext) throws -> IdentityProfile? {
        var descriptor = FetchDescriptor<IdentityProfile>(
            predicate: #Predicate { profile in
                profile.scope == "default"
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchActiveStateSnapshot(in context: ModelContext) throws -> ActiveStateSnapshot? {
        var descriptor = FetchDescriptor<ActiveStateSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.scope == "default"
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchPatterns(in context: ModelContext) throws -> [Pattern] {
        try context.fetch(
            FetchDescriptor<Pattern>(
                sortBy: [SortDescriptor(\.lastReinforced, order: .reverse)]
            )
        )
    }

    private func aggregate(_ stats: [SummaryKeyStats]) -> SummaryKeyStats {
        guard !stats.isEmpty else {
            return .empty
        }

        let totalCalories = stats.reduce(0) { $0 + $1.calories }
        let totalProtein = stats.reduce(0) { $0 + $1.protein }
        let count = stats.count

        return SummaryKeyStats(
            calories: Int((Double(totalCalories) / Double(count)).rounded()),
            protein: Int((Double(totalProtein) / Double(count)).rounded()),
            trained: stats.contains(where: \.trained),
            hrv: stats.reversed().compactMap(\.hrv).first,
            sleep: stats.reversed().compactMap(\.sleep).first
        )
    }

    private func computeActiveStateEnrichment(
        identityFacts: [String: String],
        dailyStats: [DailyStatSnapshot],
        extendedMetrics: [StoredMetric],
        today: Date
    ) -> ActiveStateEnrichment {
        let goalFrame = computeGoalFrame(
            identityFacts: identityFacts,
            extendedMetrics: extendedMetrics,
            today: today
        )
        let weightTrend = computeWeightTrend(metrics: extendedMetrics, today: today)
        let intake = computeIntake(
            dailyStats: dailyStats,
            calorieTarget: goalFrame?.calorieTarget,
            proteinTarget: goalFrame?.proteinTarget
        )
        let training = computeTrainingBlock(dailyStats: dailyStats)
        let recovery = computeRecoveryBlock(
            metrics: extendedMetrics,
            dailyStats: dailyStats,
            today: today
        )
        let sufficiency = computeDataSufficiency(
            metrics: extendedMetrics,
            dailyStats: dailyStats,
            goalFrame: goalFrame,
            weightTrend: weightTrend
        )

        return ActiveStateEnrichment(
            goalFrame: goalFrame,
            weightTrend: weightTrend,
            intake: intake,
            training: training,
            recovery: recovery,
            dataSufficiency: sufficiency
        )
    }

    private func computeGoalFrame(
        identityFacts: [String: String],
        extendedMetrics: [StoredMetric],
        today: Date
    ) -> GoalFrameBlock? {
        let name = identityFacts["name"]
        let framing = identityFacts["goal_framing"]
        let originStory = identityFacts["origin_story"]
        let approach = identityFacts["approach"]
        let goalWeight = Self.parseWeightKg(identityFacts["goal_weight"])
        let storedCurrentWeight = Self.parseWeightKg(identityFacts["current_weight"])
        let latestWeightMetric = extendedMetrics
            .filter { $0.type.lowercased() == "weight" }
            .max { $0.date < $1.date }
        let latestWeight = storedCurrentWeight
            ?? Self.parseWeightKg(latestWeightMetric?.value)
        let goalStart = identityFacts["goal_start_date"]
            ?? identityFacts["cut_start_date"]
        let daysSince: Int? = goalStart.flatMap { dateString in
            guard let parsed = Self.dayFormatter.date(from: dateString) else { return nil }
            return calendar.dateComponents([.day], from: parsed, to: today).day
        }
        let calorieTarget = Int(identityFacts["calorie_target"] ?? "") ?? nil
        let proteinTarget = Int(identityFacts["protein_target"] ?? "") ?? nil
        let gap: Double? = {
            guard let goalWeight, let latestWeight else { return nil }
            return (latestWeight - goalWeight).rounded(digits: 1)
        }()

        if name == nil, framing == nil, originStory == nil, approach == nil, goalWeight == nil,
           latestWeight == nil, goalStart == nil, calorieTarget == nil, proteinTarget == nil {
            return nil
        }

        return GoalFrameBlock(
            name: name,
            framing: framing,
            originStory: originStory,
            approach: approach,
            goalWeightKg: goalWeight,
            currentWeightKg: latestWeight.map { $0.rounded(digits: 1) },
            weightGapKg: gap,
            goalStartDate: goalStart,
            daysSinceGoalStart: daysSince,
            calorieTarget: calorieTarget,
            proteinTarget: proteinTarget
        )
    }

    private func computeWeightTrend(metrics: [StoredMetric], today: Date) -> WeightTrendBlock? {
        let weights = metrics
            .filter { $0.type.lowercased() == "weight" }
            .compactMap { metric -> (date: Date, kg: Double)? in
                guard let kg = Self.parseWeightKg(metric.value) else { return nil }
                return (metric.date, kg)
            }
            .sorted { $0.date < $1.date }

        guard !weights.isEmpty else { return nil }

        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: today) ?? today

        let lastSeven = weights.filter { $0.date >= sevenDaysAgo }
        let priorSeven = weights.filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }
        let lastTwentyEight = weights.filter { $0.date >= twentyEightDaysAgo }

        let sevenMean = mean(lastSeven.map(\.kg))?.rounded(digits: 2)
        let priorSevenMean = mean(priorSeven.map(\.kg))?.rounded(digits: 2)
        let sevenDelta: Double? = {
            guard let sevenMean, let priorSevenMean else { return nil }
            return (sevenMean - priorSevenMean).rounded(digits: 2)
        }()
        let twentyEightMean = mean(lastTwentyEight.map(\.kg))?.rounded(digits: 2)
        let twentyEightDelta: Double? = {
            guard let first = lastTwentyEight.first?.kg,
                  let last = lastTwentyEight.last?.kg,
                  lastTwentyEight.count >= 2 else { return nil }
            return (last - first).rounded(digits: 2)
        }()

        let note: String? = {
            if lastSeven.count < 3 {
                return "Fewer than 3 weigh-ins in the last 7 days; 7-day direction is not reliable yet."
            }
            if lastTwentyEight.count < 8 {
                return "Fewer than 8 weigh-ins in the last 28 days; trend is still coarse."
            }
            return nil
        }()

        return WeightTrendBlock(
            sevenDayMeanKg: sevenMean,
            priorSevenDayMeanKg: priorSevenMean,
            sevenDayDeltaKg: sevenDelta,
            twentyEightDayMeanKg: twentyEightMean,
            twentyEightDayDeltaKg: twentyEightDelta,
            pointCount: weights.count,
            note: note
        )
    }

    private func computeIntake(
        dailyStats: [DailyStatSnapshot],
        calorieTarget: Int?,
        proteinTarget: Int?
    ) -> IntakeBlock {
        let loggedDays = dailyStats.filter { $0.loggedAnything && ($0.calories > 0 || $0.protein > 0) }
        let calorieMean = mean(loggedDays.map { Double($0.calories) }).map { Int($0.rounded()) } ?? 0
        let proteinMean = mean(loggedDays.map { Double($0.protein) }).map { Int($0.rounded()) } ?? 0
        let calorieDelta = calorieTarget.map { calorieMean - $0 }
        let proteinDelta = proteinTarget.map { proteinMean - $0 }
        return IntakeBlock(
            sevenDayCalorieMean: calorieMean,
            sevenDayProteinMean: proteinMean,
            calorieDeltaVsTarget: calorieDelta,
            proteinDeltaVsTarget: proteinDelta,
            loggedDaysInWindow: loggedDays.count
        )
    }

    private func computeTrainingBlock(dailyStats: [DailyStatSnapshot]) -> TrainingBlock {
        let trainedDays = dailyStats.filter(\.trained).count
        return TrainingBlock(
            trainedDaysInWindow: trainedDays,
            mainLifts: [],
            note: trainedDays == 0 ? "No training logged in the 7-day window." : nil
        )
    }

    private func computeRecoveryBlock(
        metrics: [StoredMetric],
        dailyStats: [DailyStatSnapshot],
        today: Date
    ) -> RecoveryBlock {
        let hrvValues = metrics
            .filter { $0.type.lowercased() == "hrv" }
            .compactMap { Double($0.value) }
        let hrvMean = mean(hrvValues)?.rounded(digits: 1)
        let hrvStddev = standardDeviation(hrvValues)?.rounded(digits: 1)
        let hrvNote: String? = {
            guard hrvValues.count < 14 else { return nil }
            return "HRV baseline not yet established — only \(hrvValues.count) days of data, need 14+."
        }()

        let recentSleepMinutes = dailyStats.compactMap { Self.parseDurationMinutes($0.sleep) }
        let sleepMean = mean(recentSleepMinutes.map(Double.init)).map { Int($0.rounded()) }
        let sleepNote: String? = recentSleepMinutes.count < 3
            ? "Fewer than 3 sleep readings in the 7-day window."
            : nil

        return RecoveryBlock(
            hrvBaselineMean: hrvValues.count >= 14 ? hrvMean : nil,
            hrvBaselineStddev: hrvValues.count >= 14 ? hrvStddev : nil,
            hrvDaysInSample: hrvValues.count,
            sleepSevenDayMeanMinutes: sleepMean,
            hrvNote: hrvNote,
            sleepNote: sleepNote
        )
    }

    private func computeDataSufficiency(
        metrics: [StoredMetric],
        dailyStats: [DailyStatSnapshot],
        goalFrame: GoalFrameBlock?,
        weightTrend: WeightTrendBlock?
    ) -> DataSufficiencyBlock {
        let weightCount = metrics.filter { $0.type.lowercased() == "weight" }.count
        let hrvCount = metrics.filter { $0.type.lowercased() == "hrv" }.count
        let sleepCount = dailyStats.filter { $0.sleep != nil }.count

        var flags: [String] = []
        if goalFrame?.goalWeightKg == nil {
            flags.append("goal_weight not set")
        }
        if goalFrame?.calorieTarget == nil {
            flags.append("calorie_target not set")
        }
        if goalFrame?.proteinTarget == nil {
            flags.append("protein_target not set")
        }
        if goalFrame?.goalStartDate == nil {
            flags.append("goal_start_date not set")
        }
        if weightCount < 7 {
            flags.append("weight_data_thin (\(weightCount) days)")
        }
        if hrvCount < 14 {
            flags.append("hrv_baseline_not_established (\(hrvCount) days)")
        }

        return DataSufficiencyBlock(
            weightDataDays: weightCount,
            hrvDataDays: hrvCount,
            sleepDataDays: sleepCount,
            conversationTurnsInWindow: 0,
            flags: flags
        )
    }

    private func computeDailyEnrichment(
        identityFacts: [String: String],
        today: StructuredDayData,
        todayMessages: [ConversationSnippet],
        baselineStats: [DailyStatSnapshot],
        priorWorkouts: [StoredWorkoutSet],
        priorMetrics: [StoredMetric]
    ) -> DailyEnrichment {
        let calorieTarget = Int(identityFacts["calorie_target"] ?? "")
        let proteinTarget = Int(identityFacts["protein_target"] ?? "")
        let todayCalories = today.keyStats.calories
        let todayProtein = today.keyStats.protein
        let calorieDelta = calorieTarget.map { todayCalories - $0 }
        let proteinDelta = proteinTarget.map { todayProtein - $0 }

        let baselineCalMean = mean(baselineStats.map { Double($0.calories) }) ?? 0
        let baselineProteinMean = mean(baselineStats.map { Double($0.protein) }) ?? 0
        let calVsBaseline = classifyVsBaseline(
            value: Double(todayCalories),
            baseline: baselineCalMean,
            tolerance: 0.15
        )
        let proteinVsBaseline = classifyVsBaseline(
            value: Double(todayProtein),
            baseline: baselineProteinMean,
            tolerance: 0.15
        )

        let hrvValues = priorMetrics
            .filter { $0.type.lowercased() == "hrv" }
            .compactMap { Double($0.value) }
        let hrvBaseline = mean(hrvValues)?.rounded(digits: 1)
        let todayHrv = today.keyStats.hrv.flatMap(Double.init)
        let hrvVsBaseline: String? = {
            guard let todayHrv, let hrvBaseline, hrvValues.count >= 7 else { return nil }
            return classifyVsBaseline(value: todayHrv, baseline: hrvBaseline, tolerance: 0.15)
        }()

        let todaySleepMin = Self.parseDurationMinutes(today.keyStats.sleep)
        let baselineSleepValues = priorMetrics
            .filter { $0.type.lowercased() == "sleep" }
            .compactMap { Self.parseDurationMinutes($0.value) }
        let baselineSleepMean = mean(baselineSleepValues.map(Double.init))
        let sleepVsBaseline: String? = {
            guard let todaySleepMin, let baselineSleepMean, baselineSleepValues.count >= 5 else {
                return nil
            }
            return classifyVsBaseline(
                value: Double(todaySleepMin),
                baseline: baselineSleepMean,
                tolerance: 0.10
            )
        }()

        let progression = trainingProgressionNotes(
            today: today.workoutSets,
            priorWorkouts: priorWorkouts
        )

        let flags = conversationFlags(
            messages: todayMessages,
            todayMarkdown: summarizedText(from: today)
        )

        return DailyEnrichment(
            calorieTarget: calorieTarget,
            calorieDelta: calorieDelta,
            proteinTarget: proteinTarget,
            proteinDelta: proteinDelta,
            caloriesVsBaseline: baselineStats.isEmpty ? nil : calVsBaseline,
            proteinVsBaseline: baselineStats.isEmpty ? nil : proteinVsBaseline,
            hrvBaselineMean: hrvValues.count >= 7 ? hrvBaseline : nil,
            hrvVsBaseline: hrvVsBaseline,
            sleepVsBaseline: sleepVsBaseline,
            trainingProgression: progression,
            conversationFlags: flags,
            goalFraming: identityFacts["goal_framing"]
        )
    }

    private func trainingProgressionNotes(
        today: [StoredWorkoutSet],
        priorWorkouts: [StoredWorkoutSet]
    ) -> [TrainingProgressionNote] {
        let exercises = Set(today.map(\.exercise))
        var notes: [TrainingProgressionNote] = []

        for exercise in exercises.sorted() {
            let todaySets = today.filter { $0.exercise == exercise }
            guard let latestToday = todaySets.max(by: { $0.date < $1.date }) else { continue }
            let todayLoad = Self.parseLoadText(from: latestToday.summary) ?? latestToday.summary

            let priorSameExercise = priorWorkouts
                .filter { $0.exercise == exercise }
                .sorted { $0.date > $1.date }
                .first
            let priorLoad = priorSameExercise.flatMap { Self.parseLoadText(from: $0.summary) }
            let priorDate = priorSameExercise.map { Self.dayString($0.date) }
            let direction: String = {
                guard let priorLoad,
                      let todayKg = Self.loadNumeric(todayLoad),
                      let priorKg = Self.loadNumeric(priorLoad) else {
                    return priorSameExercise == nil ? "baseline" : "unknown"
                }
                if todayKg > priorKg { return "up" }
                if todayKg < priorKg { return "down" }
                return "flat"
            }()

            notes.append(
                TrainingProgressionNote(
                    exercise: exercise,
                    todayLoad: todayLoad,
                    priorLoad: priorLoad,
                    priorDate: priorDate,
                    direction: direction
                )
            )
        }

        return notes
    }

    private func conversationFlags(messages: [ConversationSnippet], todayMarkdown: String) -> [String] {
        let combined = (messages.map(\.content) + [todayMarkdown])
            .joined(separator: " ")
            .lowercased()
        var flags: [String] = []
        let alcoholTerms = ["beer", "beers", "wine", "cocktail", "drinks", "drunk", "hungover"]
        let travelTerms = ["travel", "flight", "airport", "hotel", "trip"]
        let socialTerms = ["friends", "dinner out", "restaurant", "birthday", "wedding", "social"]
        let moodTerms = ["feeling gross", "feeling off", "low mood", "flat", "anxious", "tired", "exhausted"]
        let painTerms = ["shoulder", "knee", "back pain", "hurt", "pain", "injured"]
        let prTerms = ["pr ", "personal best", "first time"]

        if alcoholTerms.contains(where: combined.contains) { flags.append("alcohol_mentioned") }
        if travelTerms.contains(where: combined.contains) { flags.append("travel_mentioned") }
        if socialTerms.contains(where: combined.contains) { flags.append("social_event_mentioned") }
        if moodTerms.contains(where: combined.contains) { flags.append("mood_flag") }
        if painTerms.contains(where: combined.contains) { flags.append("pain_or_injury_mentioned") }
        if prTerms.contains(where: combined.contains) { flags.append("possible_pr") }
        return flags
    }

    private func summarizedText(from day: StructuredDayData) -> String {
        let mealsText = day.meals.map(\.descriptionText).joined(separator: " ")
        let workoutsText = day.workoutSets
            .map { "\($0.exercise) \($0.summary) \($0.notes ?? "")" }
            .joined(separator: " ")
        let metricsText = day.metrics
            .map { "\($0.type) \($0.value) \($0.context ?? "")" }
            .joined(separator: " ")
        return [mealsText, workoutsText, metricsText].joined(separator: " ")
    }

    private func classifyVsBaseline(value: Double, baseline: Double, tolerance: Double) -> String {
        guard baseline > 0 else { return "unknown" }
        let upper = baseline * (1 + tolerance)
        let lower = baseline * (1 - tolerance)
        if value > upper { return "high" }
        if value < lower { return "low" }
        return "normal"
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let avg = mean(values) else { return nil }
        let variance = values.reduce(0.0) { $0 + pow($1 - avg, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    private func encodePrompt<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ClaudeClientError.invalidResponse
        }
        return string
    }

    private func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from responseText: String
    ) throws -> T {
        let cleaned = normalizedJSONText(from: responseText)
        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = Self.iso8601.date(from: rawValue) ?? Self.dayFormatter.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date: \(rawValue)"
            )
        }

        return try decoder.decode(type, from: data)
    }

    private func normalizedJSONText(from responseText: String) -> String {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            body = lines
                .dropFirst()
                .dropLast()
                .joined(separator: "\n")
        } else {
            body = trimmed
        }

        guard
            let startIndex = body.firstIndex(where: { $0 == "{" || $0 == "[" }),
            let endIndex = body.lastIndex(where: { $0 == "}" || $0 == "]" })
        else {
            return body
        }

        return String(body[startIndex ... endIndex])
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func parseWeightKg(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw
            .lowercased()
            .replacingOccurrences(of: "kg", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    static func parseDurationMinutes(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let lowered = raw.lowercased()
        let pattern = #"^\s*(\d+)\s*h\s*(?:(\d+)\s*m)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: lowered.utf16.count)
        guard let match = regex.firstMatch(in: lowered, range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        let hoursRange = match.range(at: 1)
        guard let hoursSwiftRange = Range(hoursRange, in: lowered),
              let hours = Int(lowered[hoursSwiftRange]) else {
            return nil
        }
        var minutes = 0
        if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound,
           let minutesSwiftRange = Range(match.range(at: 2), in: lowered) {
            minutes = Int(lowered[minutesSwiftRange]) ?? 0
        }
        return hours * 60 + minutes
    }

    static func loadNumeric(_ loadText: String) -> Double? {
        let trimmed = loadText.lowercased()
            .replacingOccurrences(of: "kg", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    private static func parseLoadText(from summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        if lowercased.contains("bw") {
            return "bw"
        }

        let patterns = [
            #"@\s*(\d+(?:\.\d+)?)\s*kg"#,
            #"(\d+(?:\.\d+)?)\s*kg\s*[×x]"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: trimmed,
                    range: NSRange(location: 0, length: trimmed.utf16.count)
                ),
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: trimmed)
            else {
                continue
            }
            return "\(trimmed[range])kg"
        }

        return nil
    }

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func timestampString(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct ActiveStatePromptInput: Encodable {
    let windowStart: String
    let windowEnd: String
    let todayMarkdown: String
    let dailyStats: [DailyStatSnapshot]
    let latestMetrics: [MetricSnapshot]
    let trainingStreakDays: Int
    let loggingStreakDays: Int
    let workingWeights: [WorkingWeightSnapshot]
    let preComputedContext: ActiveStateEnrichment
}

private struct DailySummaryPromptInput: Encodable {
    let date: String
    let keyStats: SummaryKeyStats
    let todayMarkdown: String
    let messages: [ConversationSnippet]
    let preComputedContext: DailyEnrichment
}

struct ActiveStateEnrichment: Encodable {
    let goalFrame: GoalFrameBlock?
    let weightTrend: WeightTrendBlock?
    let intake: IntakeBlock
    let training: TrainingBlock
    let recovery: RecoveryBlock
    let dataSufficiency: DataSufficiencyBlock
}

struct GoalFrameBlock: Encodable {
    let name: String?
    let framing: String?
    let originStory: String?
    let approach: String?
    let goalWeightKg: Double?
    let currentWeightKg: Double?
    let weightGapKg: Double?
    let goalStartDate: String?
    let daysSinceGoalStart: Int?
    let calorieTarget: Int?
    let proteinTarget: Int?
}

struct WeightTrendBlock: Encodable {
    let sevenDayMeanKg: Double?
    let priorSevenDayMeanKg: Double?
    let sevenDayDeltaKg: Double?
    let twentyEightDayMeanKg: Double?
    let twentyEightDayDeltaKg: Double?
    let pointCount: Int
    let note: String?
}

struct IntakeBlock: Encodable {
    let sevenDayCalorieMean: Int
    let sevenDayProteinMean: Int
    let calorieDeltaVsTarget: Int?
    let proteinDeltaVsTarget: Int?
    let loggedDaysInWindow: Int
}

struct TrainingBlock: Encodable {
    let trainedDaysInWindow: Int
    let mainLifts: [String]
    let note: String?
}

struct RecoveryBlock: Encodable {
    let hrvBaselineMean: Double?
    let hrvBaselineStddev: Double?
    let hrvDaysInSample: Int
    let sleepSevenDayMeanMinutes: Int?
    let hrvNote: String?
    let sleepNote: String?
}

struct DataSufficiencyBlock: Encodable {
    let weightDataDays: Int
    let hrvDataDays: Int
    let sleepDataDays: Int
    let conversationTurnsInWindow: Int
    let flags: [String]
}

struct DailyEnrichment: Encodable {
    let calorieTarget: Int?
    let calorieDelta: Int?
    let proteinTarget: Int?
    let proteinDelta: Int?
    let caloriesVsBaseline: String?
    let proteinVsBaseline: String?
    let hrvBaselineMean: Double?
    let hrvVsBaseline: String?
    let sleepVsBaseline: String?
    let trainingProgression: [TrainingProgressionNote]
    let conversationFlags: [String]
    let goalFraming: String?
}

struct TrainingProgressionNote: Encodable {
    let exercise: String
    let todayLoad: String
    let priorLoad: String?
    let priorDate: String?
    let direction: String
}

private struct PatternPromptInput: Encodable {
    let summaries: [SummarySnapshot]
    let currentPatterns: [PatternSnapshot]
}

private struct IdentityPromptInput: Encodable {
    let currentIdentityMarkdown: String
    let summaries: [SummarySnapshot]
    let currentPatterns: [PatternSnapshot]
}

private struct RollupPromptInput: Encodable {
    let scope: String
    let startDate: String
    let endDate: String
    let aggregateStats: SummaryKeyStats
    let entries: [RollupEntrySnapshot]
}

private struct DailyStatSnapshot: Encodable {
    let date: String
    let calories: Int
    let protein: Int
    let trained: Bool
    let hrv: String?
    let sleep: String?
    let loggedAnything: Bool
}

private struct MetricSnapshot: Encodable {
    let type: String
    let value: String
    let context: String?
    let observedAt: String
}

private struct WorkingWeightSnapshot: Encodable, Equatable {
    let exercise: String
    let loadText: String
    let observedAt: String
    let summary: String
}

private struct ConversationSnippet: Encodable {
    let role: String
    let content: String
    let date: String
}

private struct SummarySnapshot: Encodable {
    let date: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

private struct PatternSnapshot: Encodable {
    let key: String
    let description: String
    let evidenceNote: String
    let confidence: PatternConfidence
    let firstObserved: String
    let lastReinforced: String
}

private struct RollupEntrySnapshot: Encodable {
    let date: String
    let summaryText: String
    let keyStats: SummaryKeyStats
}

private struct PatternMaintenanceResponse: Decodable {
    let operations: [PatternOperation]
}

private struct PatternOperation: Decodable {
    let action: PatternOperationAction
    let key: String
    let description: String?
    let evidenceNote: String
    let confidence: PatternConfidence?
    let firstObserved: Date?
    let lastReinforced: Date?
}

private enum PatternOperationAction: String, Decodable {
    case add
    case update
    case remove
}

private struct IdentityProposalResponse: Decodable {
    let proposals: [IdentityProposal]
}

private struct IdentityProposal: Decodable {
    let kind: IdentityProposalKind
    let confidence: PatternConfidence
    let key: String
    let value: String
    let rationale: String
}

private enum IdentityProposalKind: String, Decodable {
    case factual
    case interpretive
}

private extension Double {
    func rounded(digits: Int) -> Double {
        let multiplier = pow(10.0, Double(digits))
        return (self * multiplier).rounded() / multiplier
    }
}
