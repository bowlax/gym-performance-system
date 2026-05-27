import SwiftUI
import SwiftData

@main
struct GymPerformanceApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try ModelContainer.gymPerformanceContainer()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .modelContainer(modelContainer)
    }
}
