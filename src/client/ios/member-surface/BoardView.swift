import SwiftUI
import Charts

struct BoardView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var exercises: [ExerciseModel] = []
    @State private var pbByExerciseId: [UUID: PersonalBestModel] = [:]
    @State private var exerciseIdsWithHistory: Set<UUID> = []
    @State private var pbEntryExerciseId: UUID?
    @State private var progressionExerciseId: UUID?
    @State private var sessions: [SessionModel] = []
    @State private var showInfoSheet = false
    @State private var trainingChartScrollPosition = Date()
    @State private var trainingChartVisibleDomainLength: TimeInterval = 3 * 30 * 24 * 60 * 60
    @State private var trainingChartMagnificationBase: TimeInterval?

    private var hasAnyPB: Bool { !pbByExerciseId.isEmpty }

    private var trainingChartConfiguration: ScrollableDateChartConfiguration? {
        ScrollableDateChartConfiguration.make(earliestDataPoint: sessions.first?.date)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About and privacy")
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                AppInfoSheet()
            }
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
                trainingSection
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
                        switch BoardExerciseRouting.destination(
                            for: exercise.id,
                            currentPBByExerciseId: pbByExerciseId,
                            exerciseIdsWithHistory: exerciseIdsWithHistory
                        ) {
                        case .progression:
                            progressionExerciseId = exercise.id
                        case .manualPBEntry:
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
    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: .cardSpacing) {
            Text("Training Consistency")
                .sectionLabelStyle()

            if sessions.isEmpty {
                Text("No sessions logged yet")
                    .captionLabelStyle()
            } else if let configuration = trainingChartConfiguration {
                Chart(sessions, id: \.id) { session in
                    PointMark(
                        x: .value("Date", session.date),
                        y: .value("Training", 1.0)
                    )
                    .foregroundStyle(Color.wolfBlue)
                    .symbolSize(64)
                }
                .frame(height: 60)
                .chartYScale(domain: 0...2)
                .chartYAxis(.hidden)
                .scrollableDateChart(
                    scrollPosition: $trainingChartScrollPosition,
                    visibleDomainLength: $trainingChartVisibleDomainLength,
                    magnificationBase: $trainingChartMagnificationBase,
                    configuration: configuration
                )
                .chartXAxis {
                    trainingChartXAxis
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(.clear)
                }
            }
        }
        .standardCard()
    }

    @AxisContentBuilder
    private var trainingChartXAxis: some AxisContent {
        if sessions.count == 1, let sessionDate = sessions.first?.date {
            AxisMarks(values: [sessionDate]) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).year())
            }
        } else {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
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

    @MainActor
    private func loadBoard() async {
        do {
            exercises = try dependencies.exerciseRegistry.pbExercises()
                .sorted { $0.displayOrder < $1.displayOrder }
            let pbs = try dependencies.memberPerformance.currentPBs(memberId: dependencies.memberId)
            pbByExerciseId = Dictionary(uniqueKeysWithValues: pbs.map { ($0.exerciseId, $0) })
            exerciseIdsWithHistory = try loadExerciseIdsWithHistory(
                exercises: exercises,
                memberId: dependencies.memberId
            )
            sessions = try dependencies.performanceDataAccess.fetchSessions(memberId: dependencies.memberId)
                .sorted { $0.date < $1.date }
            configureTrainingChartViewport()
        } catch {
            exercises = []
            pbByExerciseId = [:]
            exerciseIdsWithHistory = []
            sessions = []
        }
    }

    private func configureTrainingChartViewport() {
        guard let configuration = trainingChartConfiguration else { return }
        trainingChartVisibleDomainLength = configuration.visibleDomainLength
        trainingChartScrollPosition = configuration.initialScrollPosition
    }

    private func loadExerciseIdsWithHistory(
        exercises: [ExerciseModel],
        memberId: UUID
    ) throws -> Set<UUID> {
        var ids = Set<UUID>()
        let pbExerciseIds = Set(exercises.map(\.id))

        for exercise in exercises {
            let personalBests = try dependencies.performanceDataAccess.fetchAllPBs(
                memberId: memberId,
                exerciseId: exercise.id
            )
            if !personalBests.isEmpty {
                ids.insert(exercise.id)
            }
        }

        let sessions = try dependencies.performanceDataAccess.fetchSessions(memberId: memberId)
        for session in sessions {
            let entries = try dependencies.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
            for entry in entries where pbExerciseIds.contains(entry.exerciseId) {
                let sets = try dependencies.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                if !sets.isEmpty {
                    ids.insert(entry.exerciseId)
                }
            }
        }

        return ids
    }
}

#Preview {
    BoardView()
}
