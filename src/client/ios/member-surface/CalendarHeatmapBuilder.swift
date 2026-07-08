import Foundation
import UIKit

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
        let centerX: CGFloat
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
        let year: Int
        let month: Int
        let sortOrder: Int
    }

    private struct ResolvedLabel {
        var centerX: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
        let width: CGFloat
        let candidate: LabelCandidate
    }

    private static let labelSeparation: CGFloat = 4

    static func placementCenterX(
        _ placement: MonthLabelPlacement,
        cellSize: CGFloat = 9,
        cellGap: CGFloat = 2
    ) -> CGFloat {
        placement.centerX
    }

    private static func weekIndexCenterX(
        _ weekIndex: Int,
        cellSize: CGFloat = 9,
        cellGap: CGFloat = 2
    ) -> CGFloat {
        let columnStride = cellSize + cellGap
        return CGFloat(weekIndex) * columnStride + cellSize / 2
    }

    private static func measuredLabelWidth(_ label: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 11, weight: .regular)
        let size = (label as NSString).size(withAttributes: [.font: font])
        return ceil(size.width) + 2
    }

    private static func idealCenterX(
        weeks: [HeatmapWeek],
        year: Int,
        month: Int,
        cellSize: CGFloat = 9,
        cellGap: CGFloat = 2
    ) -> CGFloat {
        let columnStride = cellSize + cellGap
        var weightedSum: CGFloat = 0
        var totalWeight: CGFloat = 0

        for (weekIndex, week) in weeks.enumerated() {
            let dayCount = week.days.filter { day in
                guard day.inRange else { return false }
                let components = calendar.dateComponents([.year, .month], from: day.date)
                return components.year == year && components.month == month
            }.count

            if dayCount > 0 {
                weightedSum += CGFloat(weekIndex) * CGFloat(dayCount)
                totalWeight += CGFloat(dayCount)
            }
        }

        guard totalWeight > 0 else { return 0 }
        return (weightedSum / totalWeight) * columnStride + cellSize / 2
    }

    private static func resolveMonthLabelPositions(
        weeks: [HeatmapWeek],
        candidates: [LabelCandidate],
        cellSize: CGFloat = 9,
        cellGap: CGFloat = 2
    ) -> [MonthLabelPlacement] {
        let sorted = candidates.sorted { $0.sortOrder < $1.sortOrder }
        let columnStride = cellSize + cellGap
        let expandBy = columnStride

        var resolved: [ResolvedLabel] = []

        for candidate in sorted {
            let minX = weekIndexCenterX(candidate.weekStartIndex, cellSize: cellSize, cellGap: cellGap)
            let maxX = weekIndexCenterX(candidate.weekEndIndex, cellSize: cellSize, cellGap: cellGap)
            let width = measuredLabelWidth(candidate.label)
            var centerX = idealCenterX(
                weeks: weeks,
                year: candidate.year,
                month: candidate.month,
                cellSize: cellSize,
                cellGap: cellGap
            )

            if let previous = resolved.last {
                let minAllowed = previous.centerX + (previous.width + width) / 2 + labelSeparation
                centerX = max(centerX, minAllowed)
            }

            let softMinX = minX - expandBy
            let softMaxX = maxX + expandBy
            centerX = min(max(centerX, softMinX), softMaxX)

            resolved.append(
                ResolvedLabel(
                    centerX: centerX,
                    minX: minX,
                    maxX: maxX,
                    width: width,
                    candidate: candidate
                )
            )
        }

        for index in stride(from: resolved.count - 2, through: 0, by: -1) {
            let next = resolved[index + 1]
            var current = resolved[index]
            let minGap = (current.width + next.width) / 2 + labelSeparation
            if next.centerX - current.centerX < minGap {
                current.centerX = next.centerX - minGap
                current.centerX = max(current.centerX, current.minX - expandBy)
                resolved[index] = current
            }
        }

        return resolved.map { item in
            MonthLabelPlacement(
                label: item.candidate.label,
                weekStartIndex: item.candidate.weekStartIndex,
                weekEndIndex: item.candidate.weekEndIndex,
                row: 0,
                centerX: item.centerX
            )
        }
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
                            year: year,
                            month: month,
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
                    year: calendar.component(.year, from: anchorDate),
                    month: calendar.component(.month, from: anchorDate),
                    sortOrder: 0
                )
            )
        }

        return resolveMonthLabelPositions(weeks: weeks, candidates: candidates)
    }
}
