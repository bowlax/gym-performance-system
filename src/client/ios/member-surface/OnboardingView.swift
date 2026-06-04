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
        .tint(Color.wolfBlue)
    }

    private var welcome: some View {
        VStack(spacing: .sectionSpacing) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.pbYellow)
            Text("GymPerformance")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Track your personal bests and training sessions. Your digital PB board.")
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                stage = .setPBs
            } label: {
                Text("Get started")
                    .primaryButtonStyle()
            }
            .padding(.horizontal)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Text("Privacy Policy")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.wolfBlue)
            }
            .padding(.bottom)
        }
    }

    private var setPBs: some View {
        Form {
            Section {
                Text("What are your current PBs?")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Add what you know. You can always update these later.")
                    .captionLabelStyle()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(exercises, id: \.id) { exercise in
                Section {
                    VStack(alignment: .leading, spacing: .cardSpacing) {
                        Text(exercise.name)
                            .exerciseTitleStyle()
                        SetInputRow(
                            value: binding(for: exercise),
                            exercise: exercise
                        )
                    }
                    .standardCard()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Section {
                Button {
                    completeOnboarding()
                } label: {
                    Text(isSaving ? "Saving..." : "Done")
                        .primaryButtonStyle(isEnabled: !isSaving)
                }
                .disabled(isSaving)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Set Your PBs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for exercise: ExerciseModel) -> Binding<SetDraftValue> {
        Binding(
            get: { drafts[exercise.id] ?? SetDraftValue.initial(for: exercise) },
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
