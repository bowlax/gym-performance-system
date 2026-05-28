import SwiftUI
import Charts

struct ProgressionView: View {
    let exercise: ExerciseModel

    @Environment(AppDependencies.self) private var dependencies

    @State private var showManualPB = false
    @State private var currentPB: PersonalBestModel?
    @State private var entries: [ProgressionEntry] = []

    private var historyPoints: [ProgressionEntry] {
        entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            }
        }
        .sheet(isPresented: $showManualPB) {
            ManualPBEntrySheet(exercise: exercise)
        }
        .task(id: dependencies.refreshID) {
            await loadProgression()
        }
    }

    private var currentPBSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current PB").font(.caption).foregroundStyle(.secondary)
            if let currentPB {
                Text(PBFormatter.formatPB(currentPB, exercise: exercise))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            } else {
                Text("No PB yet")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 6 months").font(.headline)
            if historyPoints.isEmpty {
                Text("No sessions logged in the last 6 months")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(historyPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.chartValue)
                    )
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.chartValue)
                    )
                    .foregroundStyle(point.isPB ? .yellow : .blue)
                    .symbolSize(point.isPB ? 120 : 60)
                }
                .frame(height: 220)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline)
            ForEach(entries.reversed()) { entry in
                HStack {
                    Text(PBFormatter.shortDate.string(from: entry.date))
                    Spacer()
                    Text(entry.formattedValue)
                        .font(.body.monospacedDigit())
                    if entry.isPB {
                        Text("PB")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.yellow.opacity(0.25), in: Capsule())
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    @MainActor
    private func loadProgression() async {
        do {
            let from = AppDependencies.sixMonthsAgo
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

        for summary in sessionHistory {
            sessionDates.insert(calendar.startOfDay(for: summary.sessionDate))
            merged.append(
                ProgressionEntry(
                    id: summary.set.id,
                    date: summary.sessionDate,
                    formattedValue: PBFormatter.formatSet(summary.set, exercise: exercise),
                    chartValue: PBFormatter.chartValue(set: summary.set, exercise: exercise),
                    isPB: summary.isPB
                )
            )
        }

        for pb in personalBests where pb.achievedAt >= from {
            let day = calendar.startOfDay(for: pb.achievedAt)

            if pb.entryType == .manualEntry {
                if sessionDates.contains(day) {
                    continue
                }
                merged.append(
                    ProgressionEntry(
                        id: pb.id,
                        date: pb.achievedAt,
                        formattedValue: PBFormatter.formatPB(pb, exercise: exercise),
                        chartValue: PBFormatter.chartValue(pb: pb, exercise: exercise),
                        isPB: true
                    )
                )
            } else if pb.setId == nil {
                if sessionDates.contains(day) {
                    continue
                }
                merged.append(
                    ProgressionEntry(
                        id: pb.id,
                        date: pb.achievedAt,
                        formattedValue: PBFormatter.formatPB(pb, exercise: exercise),
                        chartValue: PBFormatter.chartValue(pb: pb, exercise: exercise),
                        isPB: true
                    )
                )
            }
        }

        return merged.sorted { $0.date < $1.date }
    }
}

#Preview {
    NavigationStack {
        ProgressionView(exercise: ExerciseModel.seedData[0])
    }
}
