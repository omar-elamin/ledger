import Foundation

enum MockHistoryNarratives {
    static let thisWeek = """
    Solid week so far. Protein is holding above 140g, and you hit four \
    training sessions — the most since the restart. Bench moved from 50 \
    to 60kg on Monday. HRV dipped midweek but recovered by Friday.
    """

    static let lastWeek = """
    Good rhythm last week. Five clean days, one burger-and-fries night \
    that wasn't worth the post-meal slump. Sleep averaged seven hours. \
    Training stayed consistent; the Thursday pull was the strongest of \
    the block.
    """

    static let weekBefore = """
    Rougher week. Pizza night and a late kebab plate pushed calories \
    past target twice. HRV ran low all week — low 30s. Travel sodium \
    isn't helping. Worth watching.
    """

    static let justGettingStarted = "Just getting started."

    static func narrative(
        forWeekStartingOn weekStart: Date,
        anchorDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start else {
            return nil
        }
        let normalizedWeekStart = calendar.startOfDay(for: weekStart)
        let normalizedCurrentStart = calendar.startOfDay(for: currentWeekStart)
        let weeksBack = calendar.dateComponents(
            [.weekOfYear],
            from: normalizedWeekStart,
            to: normalizedCurrentStart
        ).weekOfYear ?? -1

        switch weeksBack {
        case 0:  return thisWeek
        case 1:  return lastWeek
        case 2:  return weekBefore
        default: return nil
        }
    }
}
