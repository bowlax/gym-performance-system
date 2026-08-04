import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies

    @State private var stage: Stage = .welcome
    @State private var exercises: [ExerciseModel] = []
    @State private var drafts: [UUID: SetDraftValue] = [:]
    @State private var isSaving = false

    /// welcome → connect offer → optional manual PB populate.
    enum Stage { case welcome, connect, setPBs }

    var body: some View {
        Group {
            switch stage {
            case .welcome:
                NavigationStack {
                    welcome
                }
                .tint(Color.wolfBlue)
            case .connect:
                ConnectFlowView(
                    onDecline: {
                        // Path A: Not now → still populate the board manually.
                        stage = .setPBs
                    },
                    onConnected: { assessment in
                        handleConnected(assessment)
                    }
                )
            case .setPBs:
                NavigationStack {
                    setPBs
                }
                .tint(Color.wolfBlue)
            }
        }
        .task {
            await loadExercises()
        }
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
                advancePastWelcome()
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
                    KeyboardDismissal.dismiss()
                    completeOnboarding(savingDrafts: true)
                } label: {
                    Text(isSaving ? "Saving..." : "Continue")
                        .primaryButtonStyle(isEnabled: !isSaving)
                }
                .buttonStyle(.borderless)
                .disabled(isSaving)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollContentBackground(.hidden)
        .selectAllOnFocus()
        .keyboardDismissible()
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

    /// Welcome → connect when cloud is configured; otherwise straight to populate
    /// (same fence as launch prompts / Settings — never offer a dead Connect button).
    private func advancePastWelcome() {
        guard ConnectFeatureAvailability.isAvailable else {
            stage = .setPBs
            return
        }
        // One-shot skip of the immediate board re-prompt after decline
        // (consumed on first launch-prompt evaluation — not permanent).
        MemberConnectionStore.offeredConnectDuringOnboarding = true
        stage = .connect
    }

    /// Path B after connect: skip populate when adopted + cloud history
    /// (`ConnectBranchAssessment.shouldSkipManualPBPopulation`); otherwise
    /// still show Set Your PBs (new / empty cloud).
    private func handleConnected(_ assessment: ConnectBranchAssessment) {
        if assessment.shouldSkipManualPBPopulation {
            completeOnboarding(savingDrafts: false)
        } else {
            stage = .setPBs
        }
    }

    private func completeOnboarding(savingDrafts: Bool) {
        guard !isSaving else { return }
        isSaving = true

        if savingDrafts {
            OnboardingPBSaver.saveDraftPBs(
                exercises: exercises,
                drafts: drafts,
                memberPerformance: dependencies.memberPerformance,
                memberId: dependencies.memberId
            )
        }

        dependencies.refresh()
        isSaving = false
        onComplete()
    }
}

#Preview {
    OnboardingView()
}
