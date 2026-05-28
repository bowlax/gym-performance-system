import Foundation
import Observation
import SwiftData

@Observable
final class AppDependencies {
    let exerciseRegistry: DefaultExerciseRegistry
    let memberPerformance: DefaultMemberPerformance
    let performanceDataAccess: SwiftDataPerformanceDataAccess
    let configurationDataAccess: SwiftDataConfigurationDataAccess
    let modelContext: ModelContext

    private(set) var refreshID = UUID()

    var memberId: UUID {
        AccessControl.currentUser().id
    }

    init(modelContext: ModelContext) throws {
        self.modelContext = modelContext
        self.configurationDataAccess = SwiftDataConfigurationDataAccess(context: modelContext)
        self.exerciseRegistry = DefaultExerciseRegistry(configurationDataAccess: configurationDataAccess)
        self.performanceDataAccess = SwiftDataPerformanceDataAccess(context: modelContext)
        self.memberPerformance = DefaultMemberPerformance(
            exerciseRegistry: exerciseRegistry,
            performanceDataAccess: performanceDataAccess
        )
        try exerciseRegistry.seedIfNeeded()
    }

    func refresh() {
        refreshID = UUID()
    }

    static var sixMonthsAgo: Date {
        Date().addingTimeInterval(-180 * 24 * 60 * 60)
    }

    static var twelveMonthsAgo: Date {
        Date().addingTimeInterval(-365 * 24 * 60 * 60)
    }
}
