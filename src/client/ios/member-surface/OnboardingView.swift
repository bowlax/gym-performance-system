import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies

    @State private var stage: Stage = .welcome
    @State private var exercises: [ExerciseModel] = []
    @State private var drafts: [UUID: SetDraftValue] = [:]
    @State private var isSaving = false

    enum Stage { case welcome, setPBs }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .welcome: welcome
                case .setPBs: setPBs
                }
            }
            .task {
                await loadExercises()
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("GymPerformance")
                .font(.largeTitle.bold())
            Text("Track your personal bests and training sessions. Your digital PB board.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                stage = .setPBs
            } label: {
                Text("Get started")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .bold()
            }
            .padding()
        }
    }

    private var setPBs: some View {
        Form {
            Section {
                Text("What are your current PBs?")
                    .font(.title2.bold())
                Text("Add what you know. You can always update these later.")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            ForEach(exercises, id: \.id) { exercise in
                Section(exercise.name) {
                    SetInputRow(
                        value: binding(for: exercise),
                        exercise: exercise
                    )
                }
            }

            Section {
                Button {
                    completeOnboarding()
                } label: {
                    Text(isSaving ? "Saving..." : "Done")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Set Your PBs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for exercise: ExerciseModel) -> Binding<SetDraftValue> {
        Binding(
            get: { drafts[exercise.id] ?? SetDraftValue.empty },
            set: { drafts[exercise.id] = $0 }
        )
    }

    @MainActor
    private func loadExercises() async {
        do {
            exercises = try dependencies.exerciseRegistry.pbExercises()
                .sorted { $0.displayOrder < $1.displayOrder }
        } catch {
            exercises = []
        }
    }

    private func completeOnboarding() {
        isSaving = true

        do {
            for exercise in exercises {
                guard let values = drafts[exercise.id]?.manualPBValues(for: exercise) else { continue }
                _ = try dependencies.memberPerformance.recordManualPB(
                    exerciseId: exercise.id,
                    memberId: dependencies.memberId,
                    weight: values.weight,
                    reps: values.reps,
                    time: values.time,
                    distance: values.distance
                )
            }
            dependencies.refresh()
            onComplete()
        } catch {
            isSaving = false
        }
    }
}

#Preview {
    OnboardingView()
}
