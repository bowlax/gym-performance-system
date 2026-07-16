import SwiftUI
import Charts

struct ProgressionView: View {
    let exercise: ExerciseModel

    @Environment(AppDependencies.self) private var dependencies

    @State private var showManualPB = false
    @State private var showResetAlert = false
    @State private var showDeleteAlert = false
    @State private var entryPendingDelete: ProgressionEntry?
    @State private var deleteAlertMessage = ""
    @State private var currentPB: PersonalBestModel?
    @State private var lifetimePB: PersonalBestModel?
    @State private var showLifetimePB = false
    @State private var emptyReason: CurrentPBEmptyReason = .neverTrained
    @State private var entries: [ProgressionEntry] = []
    @State private var loadGeneration = 0
    @State private var chartScrollPosition = Date()
    @State private var visibleDomainLength: TimeInterval = 3 * 30 * 24 * 60 * 60
    @State private var magnificationBase: TimeInterval?

    private var mostRecentPBPoint: ProgressionEntry? {
        entries.filter { $0.isPB && !$0.isResetMarker }.max(by: { $0.date < $1.date })
    }

    private var progressionChartConfiguration: ScrollableDateChartConfiguration? {
        ScrollableDateChartConfiguration.make(
            earliestDataPoint: entries.first(where: { !$0.isResetMarker })?.date
        )
    }

    private var chartPlotEntries: [ProgressionEntry] {
        entries.filter { !$0.isResetMarker }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .sectionSpacing) {
                currentPBSection
                if showLifetimePB {
                    lifetimePBSection
                }
                chartSection
                historySection
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add PB Manually") {
                        showManualPB = true
                    }

                    if currentPB != nil {
                        Button("Reset Current PB", role: .destructive) {
                            showResetAlert = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.wolfBlue)
                }
                .accessibilityLabel("Progression actions")
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
            Text(deleteAlertMessage)
        }
        .task(id: dependencies.refreshID) {
            loadGeneration += 1
            let generation = loadGeneration
            await loadProgression(generation: generation)
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
            } else {
                Text(CurrentPBEmptyCopy.progressionTitle(for: emptyReason))
                    .pbValueStyle(size: 44)
                    .foregroundStyle(.secondary)
                if let detail = CurrentPBEmptyCopy.progressionDetail(for: emptyReason) {
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lifetimePBSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lifetime PB")
                .sectionLabelStyle()

            if let lifetimePB {
                Text(PBFormatter.formatPB(lifetimePB, exercise: exercise))
                    .pbValueStyle(size: 28)
                    .foregroundStyle(Color.primary)
                if lifetimePB.achievedAt == nil {
                    Text("Undated")
                        .captionLabelStyle()
                }
            } else {
                Text("No lifetime PB")
                    .pbValueStyle(size: 28)
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

            if chartPlotEntries.isEmpty {
                EmptyStateView(
                    symbol: "chart.line.uptrend.xyaxis",
                    message: "No exercise history yet"
                )
            } else if let configuration = progressionChartConfiguration {
                Chart(chartPlotEntries) { point in
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
                    ForEach(historyEntries) { entry in
                        historyRow(entry)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !entry.isResetMarker {
                                    Button(role: .destructive) {
                                        entryPendingDelete = entry
                                        deleteAlertMessage = deleteConfirmationMessage(for: entry)
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
                .id(historyEntries.map(\.id))
            }
        }
    }

    private var historyEntries: [ProgressionEntry] {
        entries.sorted { $0.date > $1.date }
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
            } else if entry.isResetMarker {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 3)
            }

            HStack {
                HStack(spacing: 6) {
                    Text(PBFormatter.shortDate.string(from: entry.date))
                        .captionLabelStyle()
                    if entry.isResetMarker {
                        Text("Reset")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                Spacer()
                if !entry.isResetMarker {
                    Text(entry.formattedValue)
                        .font(Font.system(.body, design: .rounded).weight(.medium))
                        .monospacedDigit()
                }
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
        .background(entry.isResetMarker ? Color(.systemGray6) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
    }

    private func deleteConfirmationMessage(for entry: ProgressionEntry) -> String {
        do {
            let derived = try dependencies.memberPerformance.deriveExerciseReadState(
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            let currentPB = derived.currentPB

            let removesCurrent: Bool = {
                guard let currentPB else { return false }
                if entry.personalBestId == currentPB.id { return true }
                if let setId = entry.setId, currentPB.setId == setId { return true }
                return false
            }()

            guard removesCurrent else {
                return "This cannot be undone."
            }

            if let projected = try dependencies.memberPerformance.projectedCurrentPBAfterDeletingHistoryEntry(
                setId: entry.setId,
                personalBestId: entry.personalBestId,
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            ) {
                return "Delete this entry? Your current PB will revert to \(PBFormatter.formatPB(projected, exercise: exercise))."
            }

            return "Delete this entry? Your board will show No PB yet for this exercise."
        } catch {
            return "This cannot be undone."
        }
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
        guard let entryPendingDelete else { return }

        do {
            try dependencies.memberPerformance.deleteHistoryEntry(
                setId: entryPendingDelete.setId,
                personalBestId: entryPendingDelete.personalBestId,
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            dependencies.refresh()
            reloadProgression()
        } catch {
            // No-op: invalid delete targets are ignored.
        }

        self.entryPendingDelete = nil
    }

    @MainActor
    private func loadProgression(generation: Int) async {
        reloadProgression()
        guard generation == loadGeneration else { return }
    }

    @MainActor
    private func reloadProgression() {
        do {
            let from = Date.distantPast
            let derived = try dependencies.memberPerformance.deriveExerciseReadState(
                memberId: dependencies.memberId,
                exerciseId: exercise.id
            )
            currentPB = derived.currentPB
            lifetimePB = derived.lifetimePB
            showLifetimePB = LifetimePBVisibility.shouldShow(
                lifetime: derived.lifetimePB,
                current: derived.currentPB,
                rule: exercise.pbRule
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
            // Match derivation / board: sets + manuals only (ignore sessionDerived leftovers).
            let hasManualHistory = personalBests.contains {
                $0.entryType == .manualEntry && $0.deletedAt == nil
            }
            let hasHistory = !sessionHistory.isEmpty || hasManualHistory
            emptyReason = CurrentPBEmptyCopy.reason(
                hasHistory: hasHistory,
                hasActiveReset: derived.resetAt != nil,
                stalenessEnabled: derived.stalenessEnabled
            )
            entries = ProgressionEntryMerger.merge(
                sessionHistory: sessionHistory,
                personalBests: personalBests,
                exercise: exercise,
                from: from,
                badgeIds: derived.badgeIds,
                resetAt: derived.resetAt
            )
            configureProgressionChartViewport()
        } catch is CancellationError {
            return
        } catch {
            // Keep existing entries visible if reload fails.
        }
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
