#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct PersonalBestRankingTests {
    private enum PBCascadeVectorFixtures {
        static let all: [PBCascadeVector] = {
            do {
                return try PBCascadeVectorLoader.load()
            } catch {
                fatalError("Failed to load PB cascade vectors: \(error)")
            }
        }()
    }

    @Test(arguments: PBCascadeVectorFixtures.all)
    func testPBCascadeVector(_ vector: PBCascadeVector) {
        let selectedId = PBCascadeVectorRunner.selectedRecordId(vector)

        #expect(
            selectedId == vector.expectedCurrentId,
            "[\(vector.id)] \(vector.description)"
        )
    }
}

#else
import Foundation
import XCTest
@testable import GymPerformance

final class PersonalBestRankingTests: XCTestCase {
    func testPBCascadeVectors() throws {
        let vectors = try PBCascadeVectorLoader.load()

        for vector in vectors {
            let selectedId = PBCascadeVectorRunner.selectedRecordId(vector)
            XCTAssertEqual(
                selectedId,
                vector.expectedCurrentId,
                "[\(vector.id)] \(vector.description)"
            )
        }
    }
}
#endif
