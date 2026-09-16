import SwiftUI

struct SessionDetailView: View {
    let session: SessionModel

    @Environment(AppDependencies.self) private var dependencies

    @State private var entries: [SessionEntryDetail] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showAddSheet = false
    @State private var celebrationPBs: [PersonalBestModel] = []
    @State private var showCelebration = false
    @State private var addError: String?

    private var alreadyAddedIds: Set<UUID> {
        Set(entries.map(\.exercise.id))
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if loadFailed {
                ContentUnavailableView(
                    "Couldn't load session",
                    systemImage: "exclamationmark.triangle"
                )
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

                    if entries.isEmpty {
                        Section {
                            Text("No exercises logged in this session.")
                                .captionLabelStyle()
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
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

                    if let addError {
                        Section {
                            Text(addError)
                                .foregroundStyle(.red)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Exercise") { showAddSheet = true }
                    .foregroundStyle(Color.wolfBlue)
                    .disabled(isLoading || loadFailed)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddExercisesToSessionSheet(
                session: session,
                alreadyAddedIds: alreadyAddedIds
            ) { result in
                handleAddResult(result)
            }
        }
        .sheet(isPresented: $showCelebration, onDismiss: {
            dependencies.refresh()
        }) {
            PBCelebrationSheet(newPBs: celebrationPBs)
        }
        .sensoryFeedback(.success, trigger: showCelebration)
        .task(id: dependencies.refreshID) {
            await loadDetail()
        }
    }

    private func handleAddResult(_ result: SessionResult) {
        addError = nil
        dependencies.syncCoordinator.syncAfterSessionSaved()
        Task {
            await loadDetail()
        }
        if result.newPBs.isEmpty {
            dependencies.refresh()
        } else {
            celebrationPBs = result.newPBs
            showCelebration = true
        }
    }

    @MainActor
    private func loadDetail() async {
        do {
            let fetchedEntries = try dependencies.performanceDataAccess.fetchExerciseEntries(sessionId: session.id)
                .filter { $0.deletedAt == nil }
            var details: [SessionEntryDetail] = []

            for entry in fetchedEntries {
                guard let exercise = try dependencies.exerciseRegistry.exercise(id: entry.exerciseId) else {
                    continue
                }

                let sets = try dependencies.performanceDataAccess.fetchSets(exerciseEntryId: entry.id)
                    .filter { $0.deletedAt == nil }
                let derived = try dependencies.memberPerformance.deriveExerciseReadState(
                    memberId: dependencies.memberId,
                    exerciseId: entry.exerciseId
                )
                let pbSetIds = Set(
                    sets.map(\.id).filter { derived.badgeIds.contains($0.uuidString) }
                )

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
            loadFailed = false
            isLoading = false
        } catch {
            entries = []
            loadFailed = true
            isLoading = false
        }
    }
}

private struct AddExercisesToSessionSheet: View {
    let session: SessionModel
    let alreadyAddedIds: Set<UUID>
    let onSaved: (SessionResult) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var draftExercises: [DraftExercise] = []
    @State private var showPicker = false
    @State private var saveError: String?
    @State private var pbByExerciseId: [UUID: PersonalBestModel] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Exercises")
                        .sectionLabelStyle()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if draftExercises.isEmpty {
                        Text("Tap Add Exercise to attach sets to this session.")
                            .captionLabelStyle()
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach($draftExercises) { $draft in
                            ExerciseCard(
                                draft: $draft,
                                currentPB: pbByExerciseId[draft.exercise.id]
                            ) {
                                draftExercises.removeAll { $0.id == draft.id }
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.wolfBlue)
                    }
                    .listRowBackground(Color.clear)
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Button(action: save) {
                        Text("Save")
                            .primaryButtonStyle(isEnabled: !draftExercises.isEmpty)
                    }
                    .disabled(draftExercises.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .selectAllOnFocus()
            .keyboardDismissible()
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.wolfBlue)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerSheet(
                    alreadyAddedIds: alreadyAddedIds.union(Set(draftExercises.map { $0.exercise.id }))
                ) { selected in
                    for exercise in selected {
                        draftExercises.append(DraftExercise(exercise: exercise))
                    }
                }
            }
            .task {
                await loadCurrentPBs()
            }
        }
        .tint(.wolfBlue)
    }

    @MainActor
    private func loadCurrentPBs() async {
        do {
            let pbs = try dependencies.memberPerformance.currentPBs(memberId: dependencies.memberId)
            pbByExerciseId = Dictionary(uniqueKeysWithValues: pbs.map { ($0.exerciseId, $0) })
        } catch {
            pbByExerciseId = [:]
        }
    }

    private func save() {
        saveError = nil

        var entries: [ExerciseEntryModel] = []
        var setsByEntryId: [UUID: [ModelSet]] = [:]

        for draft in draftExercises {
            let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: draft.exercise.id)
            let sets = draft.sets.compactMap { $0.toModelSet(exerciseEntryId: entry.id, exercise: draft.exercise) }
            guard !sets.isEmpty else { continue }
            entries.append(entry)
            setsByEntryId[entry.id] = sets
        }

        guard !entries.isEmpty else {
            saveError = "Add at least one set before saving."
            return
        }

        do {
            let result = try dependencies.memberPerformance.addExercisesToSession(
                sessionId: session.id,
                memberId: dependencies.memberId,
                entries: entries,
                sets: setsByEntryId
            )
            onSaved(result)
            dismiss()
        } catch {
            saveError = error.localizedDescription
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
