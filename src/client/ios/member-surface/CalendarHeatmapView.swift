import SwiftUI

struct CalendarHeatmapView: View {
    let data: CalendarHeatmapBuilder.Data

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let cellSize: CGFloat = 9
    private let cellGap: CGFloat = 2
    private let labelColumnWidth: CGFloat = 14
    private let gridHeight: CGFloat = 9 * 7 + 2 * 6

    private let monthLabelRowHeight: CGFloat = 16

    private var weekStride: CGFloat { cellSize + cellGap }

    var body: some View {
        HStack(alignment: .top, spacing: cellGap) {
            dayLabelColumn

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        weekGrid
                        monthLabelRow
                    }
                }
                .onAppear {
                    scrollToRecentWeeks(using: proxy)
                }
                .onChange(of: data.weeks.count) { _, _ in
                    scrollToRecentWeeks(using: proxy)
                }
            }
        }
        .accessibilityLabel("Training consistency calendar")
    }

    private var dayLabelColumn: some View {
        VStack(alignment: .trailing, spacing: cellGap) {
            ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: labelColumnWidth, height: cellSize, alignment: .trailing)
            }
        }
        .frame(height: gridHeight, alignment: .top)
    }

    private var weekGrid: some View {
        HStack(alignment: .top, spacing: cellGap) {
            ForEach(Array(data.weeks.enumerated()), id: \.element.id) { weekIndex, week in
                VStack(spacing: cellGap) {
                    ForEach(week.days) { day in
                        HeatmapCell(day: day)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
                .id(weekIndex)
            }
        }
        .frame(height: gridHeight, alignment: .top)
    }

    private var monthLabelRow: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: CGFloat(data.weeks.count) * weekStride - cellGap,
                    height: monthLabelRowHeight
                )

            ForEach(data.monthLabels) { placement in
                Text(placement.label)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize()
                    .position(
                        x: CalendarHeatmapBuilder.placementCenterX(
                            placement,
                            cellSize: cellSize,
                            cellGap: cellGap
                        ),
                        y: monthLabelRowHeight / 2
                    )
            }
        }
        .frame(height: monthLabelRowHeight)
    }

    private func scrollToRecentWeeks(using proxy: ScrollViewProxy) {
        guard let lastIndex = data.weeks.indices.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastIndex, anchor: .trailing)
        }
    }
}

private struct HeatmapCell: View {
    let day: CalendarHeatmapBuilder.HeatmapDay

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fillColor)
            .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        guard day.inRange else { return .clear }

        switch CalendarHeatmapBuilder.cellLevel(count: day.count) {
        case 0:
            return Color(.separator)
        case 1:
            return Color.wolfBlue.opacity(0.35)
        case 2:
            return Color.wolfBlue.opacity(0.55)
        case 3:
            return Color.wolfBlue.opacity(0.75)
        default:
            return Color.wolfBlue
        }
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM yyyy"
        let dateLabel = formatter.string(from: day.date)
        if day.count > 0 {
            let suffix = day.count == 1 ? "session" : "sessions"
            return "\(dateLabel), \(day.count) \(suffix)"
        }
        return "\(dateLabel), no session"
    }
}
