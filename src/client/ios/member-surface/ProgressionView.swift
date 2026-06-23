import SwiftUI
import Charts

struct ProgressionView: View {
    let exercise: ExerciseModel

    @Environment(AppDependencies.self) private var dependencies

    @State private var showManualPB = false
    @State private var showResetAlert = false
    @State private var showDeleteAlert = false
    @State private var entryPendingDelete: ProgressionEntry?
    @State private var currentPB: PersonalBestModel?
    @State private var entries: [ProgressionEntry] = []
    @State private var chartScrollPosition = Date()
    @State private var visibleDomainLength: TimeInterval = 3 * 30 * 24 * 60 * 60
    @State private var magnificationBase: TimeInterval?

    private var mostRecentPBPoint: ProgressionEntry? {
        entries.filter(\.isPB).max(by: { $0.date < $1.date })
    }

    private var progressionChartConfiguration: ScrollableDateChartConfiguration? {
        ScrollableDateChartConfiguration.make(earliestDataPoint: entries.first?.date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                currentPBSection
                chartSection
                historySection
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add PB manually") { showManualPB = true }
                    .foregroundStyle(Color.wolfBlue)
            }
        }
        .sheet(isPresented: $showManualPB) {
            ManualPBEntrySheet(exercise: exercise)
        }
        .alert("Reset Personal Best?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { resetCurrentPB() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear your current \(exercise.name) PB. Your history will be preserved.")
        }
        .alert("Delete this entry?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deletePendingEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This PB entry will be permanently removed. This cannot be undone.")
        }
        .task(id: dependencies.refreshID) {
            await loadProgression()
        }
    }

    private var currentPBSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current PB")
                .sectionLabelStyle()

            if let currentPB {
                Text(PBFormatter.formatPB(currentPB, exercise: exercise))
                    .pbValueStyle(size: 44)
                    .foregroundStyle(Color.wolfBlue)

                Button("Reset current PB") {
                    showResetAlert = true
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            } else {
                Text("No PB yet")
                    .pbValueStyle(size: 44)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: .cardSpacing) {
            Text("Exercise History")
                .exerciseTitleStyle()

            if entries.isEmpty {
                EmptyStateView(
                    symbol: "chart.line.uptrend.xyaxis",
                    message: "No exercise history yet"
                )
            } else if let configuration = progressionChartConfiguration {
                Chart(entries) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.chartValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.wolfBlue.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.chartValue)
                    )
                    .foregroundStyle(Color.wolfBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.chartValue)
                    )
                    .foregroundStyle(point.isPB ? Color.pbYellow : Color.wolfBlue.opacity(0.5))
                    .symbolSize(point.isPB ? 64 : 25)
                }
                .frame(height: 220)
                .scrollableDateChart(
                    scrollPosition: $chartScrollPosition,
                    visibleDomainLength: $visibleDomainLength,
                    magnificationBase: $magnificationBase,
                    configuration: configuration
                )
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.primary.opacity(0.08))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(.clear)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let recent = mostRecentPBPoint,
                           let xPosition = proxy.position(forX: recent.date),
                           let yPosition = proxy.position(forY: recent.chartValue) {
                            Text(recent.formattedValue)
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.wolfBlue)
                                .position(x: xPosition, y: max(yPosition - 14, 12))
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: .cardSpacing) {
            Text("History")
                .exerciseTitleStyle()

            if entries.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    message: "No exercise history yet"
                )
            } else {
                List {
                    ForEach(entries.reversed()) { entry in
                        historyRow(entry)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if entry.personalBestId != nil {
                                    Button(role: .destructive) {
                                        entryPendingDelete = entry
                                        showDeleteAlert = true
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: historyListHeight)
            }
        }
    }

    private var historyListHeight: CGFloat {
        CGFloat(entries.count) * 56
    }

    private func historyRow(_ entry: ProgressionEntry) -> some View {
        HStack(spacing: 0) {
            if entry.isPB {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.pbYellow)
                    .frame(width: 3)
            }

            HStack {
                Text(PBFormatter.shortDate.string(from: entry.date))
                    .captionLabelStyle()
                Spacer()
                Text(entry.formattedValue)
                    .font(Font.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
                if entry.isPB {
                    Text("PB")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.pbYellow.opacity(0.25), in: Capsule())
                }
            }
            .padding(.cardPadding)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
    }

    @MainActor
    private func resetCurrentPB() {
        do {
            try dependencies.memberPerformance.resetCurrentPB(
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            dependencies.refresh()
        } catch {
            // No-op: reset is safe when no current PB exists.
        }
    }

    @MainActor
    private func deletePendingEntry() {
        guard let entryPendingDelete,
              let personalBestId = entryPendingDelete.personalBestId else {
            return
        }

        do {
            try dependencies.memberPerformance.deletePersonalBest(
                id: personalBestId,
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            dependencies.refresh()
        } catch {
            // No-op: invalid delete targets are ignored.
        }

        self.entryPendingDelete = nil
    }

    @MainActor
    private func loadProgression() async {
        do {
            let from = Date.distantPast
            currentPB = try dependencies.performanceDataAccess.fetchCurrentPB(
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            let sessionHistory = try dependencies.memberPerformance.exerciseHistory(
                memberId: dependencies.memberId,
                exerciseId: exercise.id,
                from: from
            )
            let personalBests = try dependencies.performanceDataAccess.fetchAllPBs(
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            entries = mergeProgressionEntries(
                sessionHistory: sessionHistory,
                personalBests: personalBests,
                from: from
            )
            configureProgressionChartViewport()
        } catch {
            currentPB = nil
            entries = []
        }
    }

    private func mergeProgressionEntries(
        sessionHistory: [ExerciseSetSummary],
        personalBests: [PersonalBestModel],
        from: Date
    ) -> [ProgressionEntry] {
        let calendar = Calendar.current
        var merged: [ProgressionEntry] = []
        var sessionDates = Set<Date>()
        let pbBySetId = Dictionary(
            uniqueKeysWithValues: personalBests.compactMap { pb -> (UUID, UUID)? in
                guard let setId = pb.setId else { return nil }
                return (setId, pb.id)
            }
        )

        for summary in sessionHistory {
            sessionDates.insert(calendar.startOfDay(for: summary.sessionDate))
            merged.append(
                ProgressionEntry(
                    id: summary.set.id,
                    date: summary.sessionDate,
                    formattedValue: PBFormatter.formatSet(summary.set, exercise: exercise),
                    chartValue: PBFormatter.chartValue(set: summary.set, exercise: exercise),
                    isPB: summary.isPB,
                    personalBestId: pbBySetId[summary.set.id]
                )
            )
        }

        for pb in personalBests where pb.achievedAt >= from {
            let day = calendar.startOfDay(for: pb.achievedAt)

            if pb.entryType == .manualEntry {
                if sessionDates.contains(day) { continue }
                merged.append(
                    ProgressionEntry(
                        id: pb.id,
                        date: pb.achievedAt,
                        formattedValue: PBFormatter.formatPB(pb, exercise: exercise),
                        chartValue: PBFormatter.chartValue(pb: pb, exercise: exercise),
                        isPB: true,
                        personalBestId: pb.id
                    )
                )
            } else if pb.setId == nil {
                if sessionDates.contains(day) { continue }
                merged.append(
                    ProgressionEntry(
                        id: pb.id,
                        date: pb.achievedAt,
                        formattedValue: PBFormatter.formatPB(pb, exercise: exercise),
                        chartValue: PBFormatter.chartValue(pb: pb, exercise: exercise),
                        isPB: true,
                        personalBestId: pb.id
                    )
                )
            }
        }

        return merged.sorted { $0.date < $1.date }
    }

    private func configureProgressionChartViewport() {
        guard let configuration = progressionChartConfiguration else { return }
        visibleDomainLength = configuration.visibleDomainLength
        chartScrollPosition = configuration.initialScrollPosition
    }
}

#Preview {
    NavigationStack {
        ProgressionView(exercise: ExerciseModel.seedData[0])
    }
}
