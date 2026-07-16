import SwiftUI

struct BoardView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var exercises: [ExerciseModel] = []
    @State private var pbByExerciseId: [UUID: PersonalBestModel] = [:]
    @State private var exerciseIdsWithHistory: Set<UUID> = []
    @State private var resetExerciseIds: Set<UUID> = []
    @State private var stalenessEnabled = false
    @State private var pbEntryExerciseId: UUID?
    @State private var progressionExerciseId: UUID?
    @State private var sessions: [SessionModel] = []
    @State private var menuDestination: MenuDestination?
    @State private var trainingHeatmapData: CalendarHeatmapBuilder.Data?

    private enum MenuDestination: Identifiable {
        case settings
        case privacy
        case about

        var id: String {
            switch self {
            case .settings: return "settings"
            case .privacy: return "privacy"
            case .about: return "about"
            }
        }
    }

    private var hasAnyPB: Bool { !pbByExerciseId.isEmpty }

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
                    Menu {
                        Button {
                            menuDestination = .settings
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button {
                            menuDestination = .privacy
                        } label: {
                            Label("Privacy", systemImage: "hand.raised")
                        }
                        Button {
                            menuDestination = .about
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Menu")
                }
            }
            .sheet(item: $menuDestination) { destination in
                switch destination {
                case .settings:
                    AppInfoSheet()
                case .privacy:
                    NavigationStack {
                        PrivacyPolicyView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { menuDestination = nil }
                                        .foregroundStyle(Color.wolfBlue)
                                }
                            }
                    }
                    .tint(Color.wolfBlue)
                case .about:
                    NavigationStack {
                        AboutView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { menuDestination = nil }
                                        .foregroundStyle(Color.wolfBlue)
                                }
                            }
                    }
                    .tint(Color.wolfBlue)
                }
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
                        if let achievedAt = pb.achievedAt {
                            Text(PBFormatter.shortDate.string(from: achievedAt))
                                .captionLabelStyle()
                        }
                    }
                }
                .padding(.cardPadding)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
        } else {
            let reason = CurrentPBEmptyCopy.reason(
                hasHistory: exerciseIdsWithHistory.contains(exercise.id),
                hasActiveReset: resetExerciseIds.contains(exercise.id),
                stalenessEnabled: stalenessEnabled
            )
            HStack {
                Text(exercise.name)
                    .exerciseTitleStyle()
                Spacer()
                Text(CurrentPBEmptyCopy.boardCaption(for: reason))
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
            } else if let trainingHeatmapData {
                CalendarHeatmapView(data: trainingHeatmapData)
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

    @MainActor
    private func loadBoard() async {
        do {
            exercises = try dependencies.exerciseRegistry.pbExercises()
                .sorted { $0.displayOrder < $1.displayOrder }
            let pbs = try dependencies.memberPerformance.currentPBs(memberId: dependencies.memberId)
            pbByExerciseId = Dictionary(uniqueKeysWithValues: pbs.map { ($0.exerciseId, $0) })
            if let seconds = PBReadDerivation.lastBoardDerivationSeconds {
                print(String(format: "[PBReadDerivation] board derive across %d exercises: %.3fms", exercises.count, seconds * 1000))
            }
            exerciseIdsWithHistory = try loadExerciseIdsWithHistory(
                exercises: exercises,
                memberId: dependencies.memberId
            )
            let staleness = try MemberState.stalenessSetting(
                in: dependencies.modelContext,
                memberId: dependencies.memberId
            )
            stalenessEnabled = staleness.enabled
            resetExerciseIds = try loadResetExerciseIds(
                exercises: exercises,
                memberId: dependencies.memberId
            )
            sessions = try dependencies.performanceDataAccess.fetchSessions(memberId: dependencies.memberId)
                .sorted { $0.date < $1.date }
            trainingHeatmapData = CalendarHeatmapBuilder.build(
                sessionDates: sessions.map(\.date)
            )
        } catch {
            exercises = []
            pbByExerciseId = [:]
            exerciseIdsWithHistory = []
            resetExerciseIds = []
            stalenessEnabled = false
            sessions = []
            trainingHeatmapData = nil
        }
    }

    /// Same pool as `PBReadDerivation.records`: live sets + non-deleted manuals.
    /// Pre-#28 `sessionDerived` PB leftovers do not count.
    private func loadExerciseIdsWithHistory(
        exercises: [ExerciseModel],
        memberId: UUID
    ) throws -> Set<UUID> {
        var ids = Set<UUID>()
        let pbExerciseIds = Set(exercises.map(\.id))

        for exercise in exercises {
            let manuals = try dependencies.performanceDataAccess.fetchAllPBs(
                memberId: memberId,
                exerciseId: exercise.id
            ).filter { $0.entryType == .manualEntry && $0.deletedAt == nil }
            if !manuals.isEmpty {
                ids.insert(exercise.id)
            }
        }

        let sessions = try dependencies.performanceDataAccess.fetchSessions(memberId: memberId)
        for session in sessions where session.deletedAt == nil {
            let entries = try dependencies.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
            for entry in entries where pbExerciseIds.contains(entry.exerciseId) && entry.deletedAt == nil {
                let sets = try dependencies.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                    .filter { $0.deletedAt == nil }
                if !sets.isEmpty {
                    ids.insert(entry.exerciseId)
                }
            }
        }

        return ids
    }

    private func loadResetExerciseIds(
        exercises: [ExerciseModel],
        memberId: UUID
    ) throws -> Set<UUID> {
        var ids = Set<UUID>()
        for exercise in exercises {
            if try PBReadDerivation.resetAtDate(
                memberId: memberId,
                exerciseId: exercise.id,
                in: dependencies.modelContext
            ) != nil {
                ids.insert(exercise.id)
            }
        }
        return ids
    }
}

#Preview {
    BoardView()
}
