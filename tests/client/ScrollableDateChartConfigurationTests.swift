#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct ScrollableDateChartConfigurationTests {
    @Test
    func addsOneWeekPaddingOnEachSideOfDataSpan() {
        let calendar = Calendar.current
        let dataStart = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let configuration = ScrollableDateChartConfiguration.make(earliestDataPoint: dataStart)

        #expect(configuration != nil)
        guard let configuration else { return }

        let expectedStart = calendar.date(byAdding: .day, value: -7, to: dataStart)!
        let expectedEnd = calendar.date(byAdding: .day, value: 7, to: Date())!

        #expect(abs(configuration.domainStart.timeIntervalSince(expectedStart)) < 1)
        #expect(abs(configuration.domainEnd.timeIntervalSince(expectedEnd)) < 1)
        #expect(configuration.totalDataSpan > configuration.domainEnd.timeIntervalSince(dataStart))
    }
}
#endif
