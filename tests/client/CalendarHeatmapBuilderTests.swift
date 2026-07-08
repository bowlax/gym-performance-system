#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct CalendarHeatmapBuilderTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    @Test
    func labelsOnlyInRangeMonths() throws {
        let data = try #require(
            CalendarHeatmapBuilder.build(
                sessionDates: [date(2026, 6, 2), date(2026, 7, 1)],
                today: date(2026, 7, 8)
            )
        )

        let labels = data.monthLabels.map(\.label)
        #expect(labels.contains("Jun"))
        #expect(labels.contains("Jul"))
        #expect(!labels.contains("May"))
    }

    @Test
    func inRangeEmptyDaysUseZeroCount() throws {
        let data = try #require(
            CalendarHeatmapBuilder.build(
                sessionDates: [date(2026, 6, 2)],
                today: date(2026, 6, 4)
            )
        )

        let inRangeDays = data.weeks.flatMap(\.days).filter(\.inRange)
        #expect(inRangeDays.contains { $0.count == 0 })
        #expect(inRangeDays.contains { $0.count == 1 })
    }

    @Test
    func singleWeekStillGetsMonthLabel() throws {
        let data = try #require(
            CalendarHeatmapBuilder.build(
                sessionDates: [date(2026, 6, 2)],
                today: date(2026, 6, 4)
            )
        )

        #expect(data.monthLabels.contains { $0.label == "Jun" })
    }
}
#endif
