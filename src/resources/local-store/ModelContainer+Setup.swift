import SwiftData

extension ModelContainer {
    static func gymPerformanceContainer() throws -> ModelContainer {
        let schema = Schema([
            UserIdentityModel.self,
            ExerciseModel.self,
            SessionModel.self,
            ExerciseEntryModel.self,
            ModelSet.self,
            PersonalBestModel.self,
            ExerciseResetModel.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}
