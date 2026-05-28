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

    private var hasAnyPB: Bool { !pbByExerciseId.isEmpty }

    private var monthlySessions: [MonthlySessionCount] {
        aggregateMonthlySessions(from: weeklySessions)
    }

    private var weeklySessionsForSelectedMonth: [WeeklySessionCount] {
        guard let selectedMonth else { return [] }
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }

        return weeklySessions.filter { week in
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
            if !hasAnyPB {
                Text("Tap any exercise to log your first PB")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .listRowSeparator(.hidden)
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
            }

            Section {
                consistencySection
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func row(for exercise: ExerciseModel) -> some View {
        if let pb = pbByExerciseId[exercise.id] {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.body)
                    Text(PBFormatter.formatPB(pb, exercise: exercise))
                        .font(.headline)
                }
                Spacer()
                Text(PBFormatter.shortDate.string(from: pb.achievedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        } else {
            HStack {
                Text(exercise.name)
                Spacer()
                Text("No PB yet").foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Consistency")
                .font(.headline)

            if monthlySessions.allSatisfy({ $0.count == 0 }) {
                Text("No sessions logged yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(monthlySessions) { month in
                    BarMark(
                        x: .value("Month", month.monthStart, unit: .month),
                        y: .value("Sessions", month.count)
                    )
                    .foregroundStyle(
                        selectedMonth.map { Calendar.current.isDate($0, equalTo: month.monthStart, toGranularity: .month) ? Color.accentColor : Color.blue }
                        ?? Color.blue
                    )
                }
                .frame(height: 180)
                .chartXSelection(value: $selectedMonth)

                if let selectedMonth {
                    Text(selectedMonth, format: .dateTime.month(.wide).year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Chart(weeklySessionsForSelectedMonth, id: \.weekStarting) { week in
                        BarMark(
                            x: .value("Week", week.weekStarting, unit: .weekOfYear),
                            y: .value("Sessions", week.count)
                        )
                    }
                    .frame(height: 140)
                }
            }
        }
        .padding(.vertical, 8)
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
                from: AppDependencies.twelveMonthsAgo
            )
        } catch {
            exercises = []
            pbByExerciseId = [:]
            weeklySessions = []
        }
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
