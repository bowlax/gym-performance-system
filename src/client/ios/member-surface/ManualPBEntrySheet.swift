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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let currentPB {
                        Text("Current PB: \(PBFormatter.formatPB(currentPB, exercise: exercise))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No PB recorded yet")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    SetInputRow(value: $draft, exercise: exercise)
                }

                if let feedback {
                    Section {
                        switch feedback {
                        case .success:
                            Label("New PB saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .notPB(let current):
                            Text("This doesn't beat your current PB of \(current). Not saved.")
                                .foregroundStyle(.secondary)
                        case .error(let message):
                            Text(message)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button("Save PB") { save() }
                        .frame(maxWidth: .infinity)
                        .bold()
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
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

    @MainActor
    private func loadCurrentPB() async {
        currentPB = try? dependencies.performanceDataAccess.fetchCurrentPB(
            memberId: dependencies.memberId,
            exerciseId: exercise.id
        )
    }

    private func save() {
        guard let values = draft.manualPBValues(for: exercise) else {
            feedback = .error("Enter a value before saving.")
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
