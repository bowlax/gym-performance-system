import Foundation
import SwiftData
@testable import GymPerformance

enum TestHelpers {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            UserIdentityModel.self,
            ExerciseModel.self,
            SessionModel.self,
            ExerciseEntryModel.self,
            ModelSet.self,
            PersonalBestModel.self
        ])

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeInMemoryContext() throws -> ModelContext {
        let container = try makeInMemoryContainer()
        return ModelContext(container)
    }

    /// Best-effort repository root resolution for tests that need to read source files.
    static func repositoryRootURL() -> URL {
        // This file is at .../tests/data/TestHelpers.swift
        // Go up: data -> tests -> repo root
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile.deletingLastPathComponent() // data
            .deletingLastPathComponent() // tests
            .deletingLastPathComponent() // repo root
    }
}

