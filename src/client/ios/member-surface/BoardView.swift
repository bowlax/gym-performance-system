import SwiftUI
import Charts

struct BoardView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var exercises: [ExerciseModel] = []
    @State private var pbByExerciseId: [UUID: PersonalBestModel] = [:]
    @State private var pbEntryExerciseId: UUID?
    @State private var progressionExerciseId: UUID?
    @State private var weeklySessions: [WeeklySessionCount] = []
    @State private var selectedMonth: Date?
    @State private var consistencyScrollPosition = Date()
    @State private var consistencyVisibleDomainLength: TimeInterval = 3 * 30 * 24 * 60 * 60
    @State private var consistencyMagnificationBase: TimeInterval?

    private var hasAnyPB: Bool { !pbByExerciseId.isEmpty }

    private var chartWeeklySessions: [WeeklySessionCount] {
        guard let firstIndex = weeklySessions.firstIndex(where: { $0.count > 0 }) else {
            return []
        }
        return Array(weeklySessions[firstIndex...])
    }

    private var chartMonthlySessions: [MonthlySessionCount] {
        aggregateMonthlySessions(from: chartWeeklySessions)
    }

    private var consistencyChartConfiguration: ScrollableDateChartConfiguration? {
        ScrollableDateChartConfiguration.make(earliestDataPoint: chartWeeklySessions.first?.weekStarting)
    }

    private var weeklySessionsForSelectedMonth: [WeeklySessionCount] {
        guard let selectedMonth else { return [] }
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }

        return chartWeeklySessions.filter { week in
            week.weekStarting >= monthInterval.start && week.weekStarting < monthInterval.end
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ProgressView()
                } else {
                    list
                }
            }
            .navigationTitle("Personal Bests")
            .task(id: dependencies.refreshID) {
                await loadBoard()
            }
            .sheet(isPresented: pbEntrySheetBinding) {
                if let exercise = exercise(for: pbEntryExerciseId) {
                    ManualPBEntrySheet(exercise: exercise) {
                        pbEntryExerciseId = nil
                    }
                }
            }
            .navigationDestination(item: $progressionExerciseId) { exerciseId in
                if let exercise = exercise(for: exerciseId) {
                    ProgressionView(exercise: exercise)
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                consistencySection
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !hasAnyPB {
                EmptyStateView(
                    symbol: "dumbbell",
                    message: "Tap any exercise to log your first PB"
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(exercises, id: \.id) { exercise in
                row(for: exercise)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if pbByExerciseId[exercise.id] != nil {
                            progressionExerciseId = exercise.id
                        } else {
                            pbEntryExerciseId = exercise.id
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func row(for exercise: ExerciseModel) -> some View {
        if let pb = pbByExerciseId[exercise.id] {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.wolfBlue)
                    .frame(width: 3)

                HStack(alignment: .top) {
                    Text(exercise.name)
                        .exerciseTitleStyle()

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(PBFormatter.formatPB(pb, exercise: exercise))
                            .pbValueStyle()
                            .foregroundStyle(Color.wolfBlue)
                        Text(PBFormatter.shortDate.string(from: pb.achievedAt))
                            .captionLabelStyle()
                    }
                }
                .padding(.cardPadding)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
        } else {
            HStack {
                Text(exercise.name)
                    .exerciseTitleStyle()
                Spacer()
                Text("No PB yet")
                    .captionLabelStyle()
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.cardPadding)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: .cardSpacing) {
            Text("Training Consistency")
                .sectionLabelStyle()

            if chartMonthlySessions.isEmpty {
                Text("No sessions logged yet")
                    .captionLabelStyle()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let configuration = consistencyChartConfiguration {
                Chart(chartMonthlySessions) { month in
                    BarMark(
                        x: .value("Month", month.monthStart, unit: .month),
                        y: .value("Sessions", month.count)
                    )
                    .foregroundStyle(
                        selectedMonth.map {
                            Calendar.current.isDate($0, equalTo: month.monthStart, toGranularity: .month)
                                ? Color.wolfBlue
                                : Color.wolfBlue.opacity(0.55)
                        } ?? Color.wolfBlue
                    )
                }
                .frame(height: 180)
                .chartXSelection(value: $selectedMonth)
                .scrollableDateChart(
                    scrollPosition: $consistencyScrollPosition,
                    visibleDomainLength: $consistencyVisibleDomainLength,
                    magnificationBase: $consistencyMagnificationBase,
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

                if let selectedMonth {
                    Text(selectedMonth, format: .dateTime.month(.wide).year())
                        .captionLabelStyle()

                    Chart(weeklySessionsForSelectedMonth, id: \.weekStarting) { week in
                        BarMark(
                            x: .value("Week", week.weekStarting, unit: .weekOfYear),
                            y: .value("Sessions", week.count)
                        )
                        .foregroundStyle(Color.wolfBlue)
                    }
                    .frame(height: 140)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.primary.opacity(0.08))
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea.background(.clear)
                    }
                }
            }
        }
        .standardCard()
    }

    private var pbEntrySheetBinding: Binding<Bool> {
        Binding(
            get: { pbEntryExerciseId != nil },
            set: { isPresented in
                if !isPresented {
                    pbEntryExerciseId = nil
                }
            }
        )
    }

    private func exercise(for id: UUID?) -> ExerciseModel? {
        guard let id else { return nil }
        return exercises.first { $0.id == id }
    }

    private func aggregateMonthlySessions(from weekly: [WeeklySessionCount]) -> [MonthlySessionCount] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]

        for week in weekly {
            let components = calendar.dateComponents([.year, .month], from: week.weekStarting)
            guard let monthStart = calendar.date(from: components) else { continue }
            counts[monthStart, default: 0] += week.count
        }

        return counts
            .map { MonthlySessionCount(monthStart: $0.key, count: $0.value) }
            .sorted { $0.monthStart < $1.monthStart }
    }

    @MainActor
    private func loadBoard() async {
        do {
            exercises = try dependencies.exerciseRegistry.pbExercises()
                .sorted { $0.displayOrder < $1.displayOrder }
            let pbs = try dependencies.memberPerformance.currentPBs(memberId: dependencies.memberId)
            pbByExerciseId = Dictionary(uniqueKeysWithValues: pbs.map { ($0.exerciseId, $0) })
            weeklySessions = try dependencies.memberPerformance.sessionConsistency(
                memberId: dependencies.memberId,
                from: Date.distantPast
            )
            configureConsistencyChartViewport()
        } catch {
            exercises = []
            pbByExerciseId = [:]
            weeklySessions = []
        }
    }

    private func configureConsistencyChartViewport() {
        guard let configuration = consistencyChartConfiguration else { return }
        consistencyVisibleDomainLength = configuration.visibleDomainLength
        consistencyScrollPosition = configuration.initialScrollPosition
    }
}

private struct MonthlySessionCount: Identifiable {
    let monthStart: Date
    let count: Int

    var id: Date { monthStart }
}

#Preview {
    BoardView()
}
