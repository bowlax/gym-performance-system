import Foundation

/// Pure PB freshness / current-lifetime derivation / historic badges (#28).
///
/// Must stay in sync with `supabase/functions/_shared/pb-derivation.ts`.
/// Governed by the shared vector files under `tests/vectors/pb-*-vectors.json`.
///
/// "Best" / badge comparisons use the same pairwise rule as `evaluatePB`
/// (mirrored here as `beats`) — the PB rule itself is not re-specified.
enum PBDerivation {
    enum Unit: String, Codable, Sendable {
        case quarters
        case months
    }

    struct StalenessSetting: Codable, Sendable, Equatable {
        var enabled: Bool
        var periods: Int
        var unit: Unit
    }

    struct Record: Codable, Sendable, Equatable {
        var id: String
        /// ISO date `YYYY-MM-DD`, or nil for undated manuals.
        var achievedAt: String?
        var weight: Double?
        var reps: Int?
        var time: Double?
        var distance: Double?
        var entryKind: String?
    }

    struct DeriveResult: Equatable {
        var currentPB: Record?
        var lifetimePB: Record?
    }

    // MARK: - Dates (UTC calendar days)

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseISODate(_ iso: String) -> Date {
        guard let date = isoFormatter.date(from: iso) else {
            fatalError("Invalid ISO date: \(iso)")
        }
        return date
    }

    static func formatISODate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func startOfPeriod(_ date: Date, unit: Unit) -> Date {
        let calendar = utcCalendar
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else {
            fatalError("Missing date components")
        }
        switch unit {
        case .months:
            return calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        case .quarters:
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))!
        }
    }

    private static func addPeriods(_ date: Date, count: Int, unit: Unit) -> Date {
        let calendar = utcCalendar
        switch unit {
        case .months:
            return calendar.date(byAdding: .month, value: count, to: date)!
        case .quarters:
            return calendar.date(byAdding: .month, value: count * 3, to: date)!
        }
    }

    /// Expiry = periodStart(achievedAt) + (periods + 1) period lengths.
    static func expiryDate(
        achievedAt: String,
        periods: Int,
        unit: Unit
    ) -> String {
        let start = startOfPeriod(parseISODate(achievedAt), unit: unit)
        return formatISODate(addPeriods(start, count: periods + 1, unit: unit))
    }

    /// Fresh when `evaluatedAt` is strictly before expiry.
    /// Undated (`achievedAt` nil) is **never** fresh — regardless of whether
    /// staleness is enabled. Deliberate: “current” is a claim about now, which
    /// an undated entry cannot support even when time-filtering is off.
    /// Lifetime remains the only place undated entries appear (TC-D20).
    static func isFresh(
        achievedAt: String?,
        staleness: StalenessSetting,
        evaluatedAt: String
    ) -> Bool {
        guard let achievedAt else { return false }
        guard staleness.enabled else { return true }
        let expiry = expiryDate(
            achievedAt: achievedAt,
            periods: staleness.periods,
            unit: staleness.unit
        )
        return evaluatedAt < expiry
    }

    // MARK: - Rule comparison (delegates to PBRuleEvaluator)

    static func beats(
        challenger: Record,
        current: Record?,
        rule: PBRule
    ) -> Bool {
        PBRuleEvaluator.isPB(
            rule: rule,
            current: current.map {
                PBRuleEvaluator.Measurement(
                    weight: $0.weight,
                    reps: $0.reps,
                    time: $0.time,
                    distance: $0.distance
                )
            },
            newSet: PBRuleEvaluator.Measurement(
                weight: challenger.weight,
                reps: challenger.reps,
                time: challenger.time,
                distance: challenger.distance
            )
        )
    }

    private static func bestRecord(from records: [Record], rule: PBRule) -> Record? {
        var best: Record?
        for record in records {
            if beats(challenger: record, current: best, rule: rule) {
                best = record
            }
        }
        return best
    }

    private static func tiesUnderRule(_ lhs: Record, _ rhs: Record, rule: PBRule) -> Bool {
        !beats(challenger: lhs, current: rhs, rule: rule)
            && !beats(challenger: rhs, current: lhs, rule: rule)
    }

    private static func moreRecentAchievedAt(challenger: Record, current: Record?) -> Bool {
        guard let current else { return true }
        guard let challengerDate = challenger.achievedAt else { return false }
        guard let currentDate = current.achievedAt else { return true }
        return challengerDate > currentDate
    }

    private static func bestCurrentRecord(from records: [Record], rule: PBRule) -> Record? {
        var best: Record?
        for record in records {
            if beats(challenger: record, current: best, rule: rule)
                || (best != nil
                    && tiesUnderRule(record, best!, rule: rule)
                    && moreRecentAchievedAt(challenger: record, current: best)) {
                best = record
            }
        }
        return best
    }

    private static func isAfterReset(achievedAt: String?, resetAt: String?) -> Bool {
        guard let resetAt else { return true }
        guard let achievedAt else { return false }
        return achievedAt > resetAt
    }

    /// currentPB = best where achievedAt > resetAt AND fresh.
    /// lifetimePB = best overall (no reset / freshness filter).
    static func derivePBs(
        rule: PBRule,
        records: [Record],
        staleness: StalenessSetting,
        resetAt: String?,
        evaluatedAt: String
    ) -> DeriveResult {
        let lifetimePB = bestRecord(from: records, rule: rule)
        let currentCandidates = records.filter { record in
            isAfterReset(achievedAt: record.achievedAt, resetAt: resetAt)
                && isFresh(
                    achievedAt: record.achievedAt,
                    staleness: staleness,
                    evaluatedAt: evaluatedAt
                )
        }
        let currentPB = bestCurrentRecord(from: currentCandidates, rule: rule)
        return DeriveResult(currentPB: currentPB, lifetimePB: lifetimePB)
    }

    /// Progression lifetime element: show iff lifetime strictly beats current
    /// under the PB rule (#28). Ties hide. Delegates to `PBRuleEvaluator` via
    /// `beats` — not record ids (equal values can have different ids).
    static func shouldShowLifetimePB(
        lifetime: Record?,
        current: Record?,
        rule: PBRule
    ) -> Bool {
        guard let lifetime else { return false }
        guard let current else { return true }
        return beats(challenger: lifetime, current: current, rule: rule)
    }

    /// Historic badges: running maximum over dated records in achievedAt order.
    static func badgeIds(rule: PBRule, records: [Record]) -> [String] {
        let dated = records
            .filter { $0.achievedAt != nil }
            .sorted { lhs, rhs in
                let left = lhs.achievedAt!
                let right = rhs.achievedAt!
                if left != right { return left < right }
                return lhs.id < rhs.id
            }

        var badged: [String] = []
        var runningMax: Record?
        for record in dated {
            if beats(challenger: record, current: runningMax, rule: rule) {
                badged.append(record.id)
                runningMax = record
            }
        }
        return badged
    }
}
