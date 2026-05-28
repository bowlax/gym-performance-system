import SwiftUI

struct LogSessionView: View {
    var switchToBoard: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies

    @State private var notes: String = ""
    @State private var calories: String = ""
    @State private var draftExercises: [DraftExercise] = []

    @State private var showPicker = false
    @State private var showHistory = false
    @State private var celebrationPBs: [PersonalBestModel] = []
    @State private var showCelebration = false
    @State private var saveError: String?
    @State private var pbByExerciseId: [UUID: PersonalBestModel] = [:]

    private let today = Date()

    var canSave: Bool {
        draftExercises.contains { draft in
            draft.sets.contains { !$0.isEmpty(for: draft.exercise) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(today, style: .date).foregroundStyle(.secondary)
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                    HStack {
                        TextField("Calories", text: $calories)
                            .keyboardType(.numberPad)
                            .selectAllOnFocus()
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }

                Section("Exercises") {
                    if draftExercises.isEmpty {
                        Text("No exercises added")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($draftExercises) { $draft in
                            ExerciseCard(
                                draft: $draft,
                                currentPB: pbByExerciseId[draft.exercise.id]
                            ) {
                                draftExercises.removeAll { $0.id == draft.id }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        }
                    }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: save) {
                        Text("Save Session")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle("Log Session")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("History") { showHistory = true }
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerSheet(
                    alreadyAddedIds: Set(draftExercises.map { $0.exercise.id })
                ) { selected in
                    for exercise in selected {
                        draftExercises.append(DraftExercise(exercise: exercise))
                    }
                }
            }
            .navigationDestination(isPresented: $showHistory) {
                SessionHistoryView()
            }
            .sheet(isPresented: $showCelebration, onDismiss: {
                resetSession()
                dependencies.refresh()
                switchToBoard()
            }) {
                PBCelebrationSheet(newPBs: celebrationPBs)
            }
            .task(id: dependencies.refreshID) {
                await loadCurrentPBs()
            }
        }
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

        let session = SessionModel(
            memberId: dependencies.memberId,
            date: today,
            notes: notes.isEmpty ? nil : notes,
            caloriesBurned: Int(calories)
        )

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
            saveError = "Add at least one exercise with a completed set."
            return
        }

        do {
            let result = try dependencies.memberPerformance.saveSession(
                session,
                entries: entries,
                sets: setsByEntryId
            )

            if result.newPBs.isEmpty {
                resetSession()
                dependencies.refresh()
                switchToBoard()
            } else {
                celebrationPBs = result.newPBs
                showCelebration = true
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func resetSession() {
        notes = ""
        calories = ""
        draftExercises = []
    }
}

struct PBCelebrationSheet: View {
    let newPBs: [PersonalBestModel]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        VStack(spacing: 24) {
            Text("New Personal Bests! 🎉")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 32)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(newPBs, id: \.id) { pb in
                    Text(rowText(for: pb))
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .bold()
            }
            .padding()
        }
        .presentationDetents([.medium, .large])
    }

    private func rowText(for pb: PersonalBestModel) -> String {
        guard let exercise = try? dependencies.exerciseRegistry.exercise(id: pb.exerciseId) else {
            return "• Unknown exercise"
        }
        let formattedValue = PBFormatter.formatPB(pb, exercise: exercise)
        return "• \(exercise.name): \(formattedValue)"
    }
}

#Preview {
    LogSessionView()
}
