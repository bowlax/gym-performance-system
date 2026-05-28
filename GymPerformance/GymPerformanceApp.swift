import SwiftUI
import SwiftData

@main
struct GymPerformanceApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies

    init() {
        do {
            let container = try ModelContainer.gymPerformanceContainer()
            self.modelContainer = container
            self.dependencies = try AppDependencies(modelContext: ModelContext(container))
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
        .modelContainer(modelContainer)
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            GymPerformanceTabView()
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}
