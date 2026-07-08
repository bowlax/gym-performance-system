import Foundation

enum CalendarHeatmapBuilder {
    struct HeatmapDay: Equatable, Identifiable {
        var id: String { dateKey }
        let date: Date
        let dateKey: String
        let count: Int
        let inRange: Bool
    }

    struct HeatmapWeek: Equatable, Identifiable {
        var id: String { weekStartKey }
        let weekStart: Date
        let weekStartKey: String
        var days: [HeatmapDay]
    }

    struct MonthLabelPlacement: Equatable, Identifiable {
        var id: String { "\(label)-\(weekStartIndex)-\(weekEndIndex)" }
        let label: String
        let weekStartIndex: Int
        let weekEndIndex: Int
        let row: Int
    }

    struct Data: Equatable {
        let weeks: [HeatmapWeek]
        let monthLabels: [MonthLabelPlacement]
        let firstSessionDate: Date
        let todayDate: Date
    }

    private static let calendar = Calendar.current

    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static func build(
        sessionDates: [Date],
        today: Date = Date()
    ) -> Data? {
        var counts: [String: Int] = [:]
        for sessionDate in sessionDates {
            let key = dateKey(startOfDay(sessionDate))
            counts[key, default: 0] += 1
        }

        guard !counts.isEmpty else { return nil }

        let sortedKeys = counts.keys.sorted()
        guard let firstSessionKey = sortedKeys.first,
              let firstSessionDate = parseDateKey(firstSessionKey) else {
            return nil
        }

        let todayDate = startOfDay(today)
        let todayKey = dateKey(todayDate)
        let gridStart = startOfWeekSunday(firstSessionDate)
        let gridEnd = endOfWeekSaturday(todayDate)

        var weeks: [HeatmapWeek] = []
        var cursor = gridStart

        while cursor <= gridEnd {
            var days: [HeatmapDay] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor) else {
                    continue
                }
                let normalized = startOfDay(day)
                let key = dateKey(normalized)
                let isFuture = key > todayKey
                let beforeFirst = key < firstSessionKey

                days.append(
                    HeatmapDay(
                        date: normalized,
                        dateKey: key,
                        count: isFuture || beforeFirst ? 0 : (counts[key] ?? 0),
                        inRange: !isFuture && !beforeFirst
                    )
                )
            }

            weeks.append(
                HeatmapWeek(
                    weekStart: cursor,
                    weekStartKey: dateKey(cursor),
                    days: days
                )
            )

            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: cursor) else {
                break
            }
            cursor = nextWeek
        }

        let monthLabels = buildMonthLabelPlacements(
            weeks: weeks,
            rangeEnd: gridEnd,
            firstSessionDate: firstSessionDate
        )

        return Data(
            weeks: weeks,
            monthLabels: monthLabels,
            firstSessionDate: firstSessionDate,
            todayDate: todayDate
        )
    }

    static func cellLevel(count: Int) -> Int {
        if count <= 0 { return 0 }
        if count == 1 { return 1 }
        if count == 2 { return 2 }
        if count == 3 { return 3 }
        return 4
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dateKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func parseDateKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components).map(startOfDay)
    }

    private static func startOfWeekSunday(_ date: Date) -> Date {
        let normalized = startOfDay(date)
        let weekday = calendar.component(.weekday, from: normalized)
        let daysFromSunday = weekday - 1
        return calendar.date(byAdding: .day, value: -daysFromSunday, to: normalized) ?? normalized
    }

    private static func endOfWeekSaturday(_ date: Date) -> Date {
        let weekStart = startOfWeekSunday(date)
        return calendar.date(byAdding: .day, value: 6, to: weekStart) ?? date
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components).map(startOfDay) ?? startOfDay(date)
    }

    private static func addMonths(_ date: Date, _ count: Int) -> Date {
        calendar.date(byAdding: .month, value: count, to: date) ?? date
    }

    private static func weekHasInRangeDayInMonth(
        _ week: HeatmapWeek,
        year: Int,
        month: Int
    ) -> Bool {
        week.days.contains { day in
            guard day.inRange else { return false }
            let components = calendar.dateComponents([.year, .month], from: day.date)
            return components.year == year && components.month == month
        }
    }

    private struct LabelCandidate {
        let label: String
        let weekStartIndex: Int
        let weekEndIndex: Int
        let sortOrder: Int
    }

    private struct PlacedMonthLabel {
        let centerX: CGFloat
        let width: CGFloat
        let row: Int
        let placement: MonthLabelPlacement
    }

    private static let estimatedCharWidth: CGFloat = 7
    private static let labelPadding: CGFloat = 4

    static func placementCenterX(
        _ placement: MonthLabelPlacement,
        cellSize: CGFloat = 9,
        cellGap: CGFloat = 2
    ) -> CGFloat {
        let stride = cellSize + cellGap
        let start = CGFloat(placement.weekStartIndex) * stride + cellSize / 2
        let end = CGFloat(placement.weekEndIndex) * stride + cellSize / 2
        return (start + end) / 2
    }

    private static func estimatedLabelWidth(_ label: String) -> CGFloat {
        CGFloat(label.count) * estimatedCharWidth + labelPadding
    }

    private static func buildMonthLabelPlacements(
        weeks: [HeatmapWeek],
        rangeEnd: Date,
        firstSessionDate: Date
    ) -> [MonthLabelPlacement] {
        guard !weeks.isEmpty else { return [] }

        var candidates: [LabelCandidate] = []
        var labeledMonths = Set<String>()
        var monthCursor = startOfMonth(firstSessionDate)
        var sortOrder = 0

        while monthCursor <= rangeEnd {
            let year = calendar.component(.year, from: monthCursor)
            let month = calendar.component(.month, from: monthCursor)
            let monthKey = "\(year)-\(month)"

            if !labeledMonths.contains(monthKey) {
                let weekIndices = weeks.enumerated().compactMap { index, week in
                    weekHasInRangeDayInMonth(week, year: year, month: month) ? index : nil
                }

                if !weekIndices.isEmpty,
                   let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                    candidates.append(
                        LabelCandidate(
                            label: monthLabelFormatter.string(from: monthStart),
                            weekStartIndex: weekIndices.min() ?? 0,
                            weekEndIndex: weekIndices.max() ?? 0,
                            sortOrder: sortOrder
                        )
                    )
                    sortOrder += 1
                    labeledMonths.insert(monthKey)
                }
            }

            monthCursor = addMonths(monthCursor, 1)
        }

        if candidates.isEmpty {
            let anchorDate = weeks
                .flatMap(\.days)
                .first(where: \.inRange)?
                .date ?? firstSessionDate
            let targetIndex = (weeks.count - 1) / 2
            candidates.append(
                LabelCandidate(
                    label: monthLabelFormatter.string(from: anchorDate),
                    weekStartIndex: targetIndex,
                    weekEndIndex: targetIndex,
                    sortOrder: 0
                )
            )
        }

        return resolveMonthLabelCollisions(candidates)
    }

    private static func resolveMonthLabelCollisions(
        _ candidates: [LabelCandidate]
    ) -> [MonthLabelPlacement] {
        let sorted = candidates.sorted {
            let leftCenter = placementCenterX(
                MonthLabelPlacement(
                    label: $0.label,
                    weekStartIndex: $0.weekStartIndex,
                    weekEndIndex: $0.weekEndIndex,
                    row: 0
                )
            )
            let rightCenter = placementCenterX(
                MonthLabelPlacement(
                    label: $1.label,
                    weekStartIndex: $1.weekStartIndex,
                    weekEndIndex: $1.weekEndIndex,
                    row: 0
                )
            )
            if leftCenter != rightCenter {
                return leftCenter < rightCenter
            }
            return $0.sortOrder < $1.sortOrder
        }

        var placed: [PlacedMonthLabel] = []
        var result: [MonthLabelPlacement] = []

        for candidate in sorted {
            let placement = MonthLabelPlacement(
                label: candidate.label,
                weekStartIndex: candidate.weekStartIndex,
                weekEndIndex: candidate.weekEndIndex,
                row: 0
            )
            let centerX = placementCenterX(placement)
            let width = estimatedLabelWidth(candidate.label)

            var chosenRow: Int?
            for row in 0..<2 {
                let collides = placed.contains { existing in
                    existing.row == row
                        && abs(centerX - existing.centerX) < (width + existing.width) / 2 + labelPadding
                }
                if !collides {
                    chosenRow = row
                    break
                }
            }

            guard let row = chosenRow else { continue }

            let resolved = MonthLabelPlacement(
                label: candidate.label,
                weekStartIndex: candidate.weekStartIndex,
                weekEndIndex: candidate.weekEndIndex,
                row: row
            )
            placed.append(
                PlacedMonthLabel(
                    centerX: centerX,
                    width: width,
                    row: row,
                    placement: resolved
                )
            )
            result.append(resolved)
        }

        return result
    }
}
