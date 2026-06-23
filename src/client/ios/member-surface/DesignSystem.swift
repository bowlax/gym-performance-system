import SwiftUI
import Charts

extension Color {
    static let wolfBlue = Color(hex: "#1A5BA6")
    static let pbYellow = Color(hex: "#FFD600")
    static let brandAccent = Color.wolfBlue
    static let achievementAccent = Color.pbYellow
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension CGFloat {
    static let cardRadius: CGFloat = 16
    static let inputRadius: CGFloat = 10
    static let chipRadius: CGFloat = 8
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
}

struct EmptyStateView: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct ScrollableDateChartConfiguration {
    let domainStart: Date
    let domainEnd: Date
    let visibleDomainLength: TimeInterval
    let totalDataSpan: TimeInterval
    let initialScrollPosition: Date

    static func make(earliestDataPoint: Date?) -> ScrollableDateChartConfiguration? {
        guard let domainStart = earliestDataPoint else { return nil }

        let domainEnd = Date()
        let totalDataSpan = domainEnd.timeIntervalSince(domainStart)
        guard totalDataSpan > 0 else {
            let minimumSpan: TimeInterval = 24 * 60 * 60
            return ScrollableDateChartConfiguration(
                domainStart: domainStart,
                domainEnd: domainEnd,
                visibleDomainLength: minimumSpan,
                totalDataSpan: minimumSpan,
                initialScrollPosition: domainEnd
            )
        }

        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: domainEnd) ?? domainEnd
        let visibleStart = max(threeMonthsAgo, domainStart)
        let visibleDomainLength = domainEnd.timeIntervalSince(visibleStart)

        return ScrollableDateChartConfiguration(
            domainStart: domainStart,
            domainEnd: domainEnd,
            visibleDomainLength: visibleDomainLength,
            totalDataSpan: totalDataSpan,
            initialScrollPosition: domainEnd
        )
    }
}

struct ScrollableDateChartModifier: ViewModifier {
    @Binding var scrollPosition: Date
    @Binding var visibleDomainLength: TimeInterval
    @Binding var magnificationBase: TimeInterval?

    let domainStart: Date
    let domainEnd: Date
    let totalDataSpan: TimeInterval

    private var minVisibleLength: TimeInterval { 7 * 24 * 60 * 60 }

    func body(content: Content) -> some View {
        content
            .chartXScale(domain: domainStart...domainEnd)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleDomainLength)
            .chartScrollPosition(x: $scrollPosition)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if magnificationBase == nil {
                            magnificationBase = visibleDomainLength
                        }
                        if let base = magnificationBase {
                            let newLength = base / scale
                            visibleDomainLength = min(max(newLength, minVisibleLength), totalDataSpan)
                        }
                    }
                    .onEnded { _ in
                        magnificationBase = nil
                    }
            )
    }
}

extension View {
    func scrollableDateChart(
        scrollPosition: Binding<Date>,
        visibleDomainLength: Binding<TimeInterval>,
        magnificationBase: Binding<TimeInterval?>,
        configuration: ScrollableDateChartConfiguration
    ) -> some View {
        modifier(
            ScrollableDateChartModifier(
                scrollPosition: scrollPosition,
                visibleDomainLength: visibleDomainLength,
                magnificationBase: magnificationBase,
                domainStart: configuration.domainStart,
                domainEnd: configuration.domainEnd,
                totalDataSpan: configuration.totalDataSpan
            )
        )
    }
}

extension View {
    func pbValueStyle(size: CGFloat = 34) -> some View {
        font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }

    func exerciseTitleStyle() -> some View {
        font(.system(.headline, design: .rounded))
    }

    func captionLabelStyle() -> some View {
        font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
    }

    func sectionLabelStyle() -> some View {
        font(.system(.caption2, design: .rounded).weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    func inputValueStyle() -> some View {
        font(Font.system(.title2, design: .rounded).weight(.medium))
            .monospacedDigit()
    }

    func standardCard() -> some View {
        padding(.cardPadding)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
    }

    func inputFieldSurface() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: .inputRadius, style: .continuous))
    }

    func primaryButtonStyle(isEnabled: Bool = true) -> some View {
        frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnabled ? Color.wolfBlue : Color.wolfBlue.opacity(0.3))
            .foregroundStyle(.white)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
    }
}
