import SwiftUI

struct SessionDetailView: View {
    let session: SessionModel

    @Environment(AppDependencies.self) private var dependencies

    @State private var entries: [SessionEntryDetail] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                ProgressView()
            } else {
                List {
                    if session.notes != nil || session.caloriesBurned != nil {
                        Section {
                            if let notes = session.notes, !notes.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                                    Text(notes)
                                }
                            }
                            if let calories = session.caloriesBurned {
                                HStack {
                                    Text("Calories")
                                    Spacer()
                                    Text("\(calories) kcal").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    ForEach(entries) { entry in
                        Section(entry.exercise.name) {
                            ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                                HStack {
                                    Text("Set \(index + 1)")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(PBFormatter.formatSet(set, exercise: entry.exercise))
                                        .font(.body.monospacedDigit())
                                    if entry.pbSetIds.contains(set.id) {
                                        Text("PB")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.yellow.opacity(0.25), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
    }

    @MainActor
    private func loadDetail() async {
        do {
            let fetchedEntries = try dependencies.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
            var details: [SessionEntryDetail] = []

            for entry in fetchedEntries {
                guard let exercise = try dependencies.exerciseRegistry.exercise(id: entry.exerciseId) else {
                    continue
                }

                let sets = try dependencies.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                let setIds = Set(sets.map(\.id))
                let pbs = try dependencies.performanceDataAccess.fetchAllPBs(
                    memberId: dependencies.memberId,
                    exerciseId: entry.exerciseId
                )
                let pbSetIds = Set(pbs.compactMap(\.setId).filter { setIds.contains($0) })

                details.append(
                    SessionEntryDetail(
                        id: entry.id,
                        exercise: exercise,
                        sets: sets,
                        pbSetIds: pbSetIds
                    )
                )
            }

            entries = details
        } catch {
            entries = []
        }
    }
}

private struct SessionEntryDetail: Identifiable {
    let id: UUID
    let exercise: ExerciseModel
    let sets: [ModelSet]
    let pbSetIds: Set<UUID>
}

#Preview {
    NavigationStack {
        SessionDetailView(
            session: SessionModel(
                memberId: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                date: Date()
            )
        )
    }
}
