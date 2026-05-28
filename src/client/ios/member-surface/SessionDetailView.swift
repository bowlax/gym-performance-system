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
                                    Text("Notes").sectionLabelStyle()
                                    Text(notes)
                                        .font(.system(.body, design: .rounded))
                                }
                                .standardCard()
                            }
                            if let calories = session.caloriesBurned {
                                HStack {
                                    Text("Calories")
                                        .exerciseTitleStyle()
                                    Spacer()
                                    Text("\(calories) kcal")
                                        .captionLabelStyle()
                                }
                                .standardCard()
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    ForEach(entries) { entry in
                        Section {
                            Text(entry.exercise.name)
                                .exerciseTitleStyle()
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                                HStack {
                                    Text("Set \(index + 1)")
                                        .captionLabelStyle()
                                    Spacer()
                                    Text(PBFormatter.formatSet(set, exercise: entry.exercise))
                                        .inputValueStyle()
                                        .font(Font.system(.body, design: .rounded).weight(.medium))
                                    if entry.pbSetIds.contains(set.id) {
                                        Text("PB")
                                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.pbYellow.opacity(0.25), in: Capsule())
                                    }
                                }
                                .padding(.vertical, 4)

                                if index < entry.sets.count - 1 {
                                    Divider()
                                        .overlay(Color.primary.opacity(0.06))
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
