import SwiftUI

struct ManualPBEntrySheet: View {
    let exercise: ExerciseModel
    /// When set, edits this manual PB in place (values + optional date).
    var editing: PersonalBestModel? = nil
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    @State private var draft = SetDraftValue.empty
    @State private var includeDate = false
    @State private var selectedDate = Date()
    @State private var feedback: Feedback?
    @State private var currentPB: PersonalBestModel?
    @State private var didLoadEditing = false

    enum Feedback: Equatable {
        case success
        case notPB(current: String)
        case error(String)
    }

    private var isEditing: Bool { editing != nil }

    private var canSave: Bool {
        draft.isValidManualPB(for: exercise)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: .sectionSpacing) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(exercise.name)
                                .font(.system(.title3, design: .rounded).weight(.semibold))

                            if isEditing {
                                Text("Edit manual PB")
                                    .captionLabelStyle()
                            } else if let currentPB {
                                Text("Current PB")
                                    .sectionLabelStyle()
                                Text(PBFormatter.formatPB(currentPB, exercise: exercise))
                                    .pbValueStyle(size: 28)
                                    .foregroundStyle(Color.wolfBlue)
                            } else {
                                Text("No current PB")
                                    .captionLabelStyle()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Include date", isOn: $includeDate)
                            if includeDate {
                                DatePicker(
                                    "Date",
                                    selection: $selectedDate,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                            } else {
                                Text(
                                    isEditing
                                        ? "Without a date this stays a lifetime-only entry and will not appear as your current PB on the board."
                                        : "Leave the date off if you only remember the value. It counts toward your lifetime best, not your current PB."
                                )
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: .cardSpacing) {
                            Text(isEditing ? "Values" : "New PB")
                                .sectionLabelStyle()
                            SetInputRow(value: $draft, exercise: exercise)
                        }
                        .standardCard()

                        if let feedback {
                            feedbackView(for: feedback)
                        }

                        Button(isEditing ? "Save Changes" : "Save PB") { save() }
                            .primaryButtonStyle(isEnabled: canSave)
                            .disabled(!canSave)
                    }
                    .padding()
                }
            }
            .selectAllOnFocus()
            .keyboardDismissible()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.wolfBlue)
                }
            }
            .onAppear {
                loadDraft()
            }
            .task(id: dependencies.refreshID) {
                await loadCurrentPB()
            }
        }
    }

    @ViewBuilder
    private func feedbackView(for feedback: Feedback) -> some View {
        switch feedback {
        case .success:
            Label(
                isEditing ? "PB updated" : "New PB saved",
                systemImage: "checkmark.circle.fill"
            )
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .standardCard()
        case .notPB(let current):
            Label {
                Text("This doesn't beat your current PB of \(current). Not saved.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .standardCard()
        case .error(let message):
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .standardCard()
        }
    }

    private func loadDraft() {
        guard !didLoadEditing else { return }
        if let editing {
            draft = SetDraftValue(
                weight: editing.weight,
                reps: editing.reps,
                timeSeconds: editing.time.map { Int($0.rounded()) },
                distance: editing.distance.map { Int($0.rounded()) }
            )
            if let achievedAt = editing.achievedAt {
                includeDate = true
                selectedDate = achievedAt
            } else {
                includeDate = false
            }
            didLoadEditing = true
        } else {
            draft = SetDraftValue.initial(for: exercise)
        }
    }

    @MainActor
    private func loadCurrentPB() async {
        currentPB = try? dependencies.memberPerformance.deriveExerciseReadState(
            memberId: dependencies.memberId,
            exerciseId: exercise.id
        ).currentPB
    }

    private func save() {
        if let message = draft.manualPBValidationMessage(for: exercise) {
            feedback = .error(message)
            return
        }

        guard let values = draft.manualPBValues(for: exercise) else {
            feedback = .error("Enter all required values before saving.")
            return
        }

        do {
            if let editing {
                try dependencies.memberPerformance.updateManualPB(
                    id: editing.id,
                    memberId: dependencies.memberId,
                    exerciseId: exercise.id,
                    weight: values.weight,
                    reps: values.reps,
                    time: values.time,
                    distance: values.distance,
                    achievedAt: includeDate ? selectedDate : nil
                )
                feedback = .success
                dependencies.refresh()
                onSaved?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
                return
            }

            let result = try dependencies.memberPerformance.recordManualPB(
                exerciseId: exercise.id,
                memberId: dependencies.memberId,
                weight: values.weight,
                reps: values.reps,
                time: values.time,
                distance: values.distance,
                achievedAt: includeDate ? selectedDate : nil
            )

            if result.isNewPB {
                feedback = .success
                dependencies.refresh()
                onSaved?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
            } else {
                let current = try dependencies.memberPerformance.deriveExerciseReadState(
                    memberId: dependencies.memberId,
                    exerciseId: exercise.id
                ).currentPB
                let currentValue = current.map { PBFormatter.formatPB($0, exercise: exercise) } ?? "none"
                feedback = .notPB(current: currentValue)
            }
        } catch {
            feedback = .error(error.localizedDescription)
        }
    }
}

#Preview {
    ManualPBEntrySheet(exercise: ExerciseModel.seedData[0])
}
