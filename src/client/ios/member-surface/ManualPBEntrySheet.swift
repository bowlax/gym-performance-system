import SwiftUI

struct ManualPBEntrySheet: View {
    let exercise: ExerciseModel
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    @State private var draft = SetDraftValue.empty
    @State private var feedback: Feedback?
    @State private var currentPB: PersonalBestModel?

    enum Feedback: Equatable {
        case success
        case notPB(current: String)
        case error(String)
    }

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

                            if let currentPB {
                                Text("Current PB")
                                    .sectionLabelStyle()
                                Text(PBFormatter.formatPB(currentPB, exercise: exercise))
                                    .pbValueStyle(size: 28)
                                    .foregroundStyle(Color.wolfBlue)
                            } else {
                                Text("No PB recorded yet")
                                    .captionLabelStyle()
                            }
                        }

                        VStack(alignment: .leading, spacing: .cardSpacing) {
                            Text("New PB")
                                .sectionLabelStyle()
                            SetInputRow(value: $draft, exercise: exercise)
                        }
                        .standardCard()

                        if let feedback {
                            feedbackView(for: feedback)
                        }

                        Button("Save PB") { save() }
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
                draft = SetDraftValue.initial(for: exercise)
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
            Label("New PB saved", systemImage: "checkmark.circle.fill")
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

    @MainActor
    private func loadCurrentPB() async {
        currentPB = try? dependencies.performanceDataAccess.fetchCurrentPB(
            memberId: dependencies.memberId,
            exerciseId: exercise.id
        )
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
            let result = try dependencies.memberPerformance.recordManualPB(
                exerciseId: exercise.id,
                memberId: dependencies.memberId,
                weight: values.weight,
                reps: values.reps,
                time: values.time,
                distance: values.distance
            )

            if result.isNewPB {
                feedback = .success
                dependencies.refresh()
                onSaved?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
            } else {
                let current = try dependencies.performanceDataAccess.fetchCurrentPB(
                    memberId: dependencies.memberId,
                    exerciseId: exercise.id
                )
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
