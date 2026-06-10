import SwiftUI

struct LogSessionView: View {
    var switchToBoard: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies

    @State private var sessionDate = Date()
    @State private var notes: String = ""
    @State private var calories: String = ""
    @State private var draftExercises: [DraftExercise] = []

    @State private var showPicker = false
    @State private var showHistory = false
    @State private var showDiscardAlert = false
    @State private var celebrationPBs: [PersonalBestModel] = []
    @State private var showCelebration = false
    @State private var saveError: String?
    @State private var pbByExerciseId: [UUID: PersonalBestModel] = [:]

    private var hasUnsavedChanges: Bool {
        !notes.isEmpty
            || !calories.isEmpty
            || !draftExercises.isEmpty
            || !Calendar.current.isDate(sessionDate, inSameDayAs: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Session")
                        .sectionLabelStyle()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    HStack {
                        Text("Date")
                            .captionLabelStyle()
                        Spacer()
                        DatePicker(
                            "Session date",
                            selection: $sessionDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                    .listRowBackground(Color.clear)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                        .selectAllOnFocus()
                        .listRowBackground(Color.clear)

                    HStack {
                        TextField("Calories", text: $calories)
                            .keyboardType(.numberPad)
                            .inputValueStyle()
                            .selectAllOnFocus()
                        Text("kcal").captionLabelStyle()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text("Exercises")
                        .sectionLabelStyle()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if draftExercises.isEmpty {
                        Text("No exercises added -- tap Add Exercise to log your sets for the board, or save this session as an attendance record.")
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
                        Text("Save Session")
                            .primaryButtonStyle()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .selectAllOnFocus()
            .keyboardDismissible()
            .navigationTitle("Log Session")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { handleCancel() }
                        .foregroundStyle(Color.wolfBlue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("History") { showHistory = true }
                        .foregroundStyle(Color.wolfBlue)
                }
            }
            .alert("Discard session?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    cancelSession()
                }
            } message: {
                Text("Your changes will be lost.")
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
            .sensoryFeedback(.success, trigger: showCelebration)
            .task(id: dependencies.refreshID) {
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

        let session = SessionModel(
            memberId: dependencies.memberId,
            date: sessionDate,
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

    private func handleCancel() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            cancelSession()
        }
    }

    private func cancelSession() {
        resetSession()
        switchToBoard()
    }

    private func resetSession() {
        sessionDate = Date()
        notes = ""
        calories = ""
        draftExercises = []
    }
}

struct PBCelebrationSheet: View {
    let newPBs: [PersonalBestModel]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    @State private var trophyScale: CGFloat = 0.5

    var body: some View {
        VStack(spacing: .sectionSpacing) {
            ZStack {
                Circle()
                    .fill(Color.pbYellow.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.pbYellow)
                    .scaleEffect(trophyScale)
            }
            .padding(.top, 24)

            Text("New Personal Bests!")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)

            VStack(spacing: .cardSpacing) {
                ForEach(newPBs, id: \.id) { pb in
                    celebrationRow(for: pb)
                }
            }
            .padding(.horizontal)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .primaryButtonStyle()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            withAnimation(.spring(duration: 0.4)) {
                trophyScale = 1.0
            }
        }
    }

    @ViewBuilder
    private func celebrationRow(for pb: PersonalBestModel) -> some View {
        if let exercise = try? dependencies.exerciseRegistry.exercise(id: pb.exerciseId) {
            HStack {
                Text(exercise.name)
                    .exerciseTitleStyle()
                Spacer()
                Text(PBFormatter.formatPB(pb, exercise: exercise))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.wolfBlue)
                    .monospacedDigit()
            }
            .padding(.cardPadding)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: .cardRadius, style: .continuous))
        }
    }
}

#Preview {
    LogSessionView()
}
