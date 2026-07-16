#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct PBDerivationTests {
    private enum Fixtures {
        static let expiry: [PBExpiryVector] = {
            do { return try PBDerivationVectorLoader.loadExpiry() }
            catch { fatalError("Failed to load expiry vectors: \(error)") }
        }()

        static let derivation: [PBDerivationVector] = {
            do { return try PBDerivationVectorLoader.loadDerivation() }
            catch { fatalError("Failed to load derivation vectors: \(error)") }
        }()

        static let badges: [PBBadgeVector] = {
            do { return try PBDerivationVectorLoader.loadBadges() }
            catch { fatalError("Failed to load badge vectors: \(error)") }
        }()

        static let lifetimeVisibility: [PBLifetimeVisibilityVector] = {
            do { return try PBDerivationVectorLoader.loadLifetimeVisibility() }
            catch { fatalError("Failed to load lifetime visibility vectors: \(error)") }
        }()
    }

    @Test
    func vectorCountsMatchSpec() throws {
        #expect(Fixtures.expiry.count == 24)
        #expect(Fixtures.derivation.count == 19)
        #expect(Fixtures.badges.count == 8)
        #expect(Fixtures.lifetimeVisibility.count == 8)
    }

    @Test(arguments: Fixtures.expiry)
    func expiryVector(_ vector: PBExpiryVector) {
        if vector.staleness.enabled {
            let expiry = PBDerivation.expiryDate(
                achievedAt: vector.achievedAt,
                periods: vector.staleness.periods,
                unit: vector.staleness.unit
            )
            #expect(expiry == vector.expectedExpiryAt, "\(vector.id) expiry")
        } else {
            #expect(vector.expectedExpiryAt == nil, "\(vector.id) disabled expiry")
        }

        let fresh = PBDerivation.isFresh(
            achievedAt: vector.achievedAt,
            staleness: vector.staleness,
            evaluatedAt: vector.evaluatedAt
        )
        #expect(fresh == vector.expectedFresh, "\(vector.id) fresh")

        if let compareAchievedAt = vector.compareAchievedAt {
            let compareExpiry = PBDerivation.expiryDate(
                achievedAt: compareAchievedAt,
                periods: vector.staleness.periods,
                unit: vector.staleness.unit
            )
            #expect(compareExpiry == vector.expectedCompareExpiryAt, "\(vector.id) compare expiry")
            let compareFresh = PBDerivation.isFresh(
                achievedAt: compareAchievedAt,
                staleness: vector.staleness,
                evaluatedAt: vector.evaluatedAt
            )
            #expect(compareFresh == vector.expectedCompareFresh, "\(vector.id) compare fresh")
        }
    }

    @Test(arguments: Fixtures.derivation)
    func derivationVector(_ vector: PBDerivationVector) {
        let result = PBDerivation.derivePBs(
            rule: PBDerivationVectorSupport.pbRule(from: vector.rule),
            records: PBDerivationVectorSupport.records(from: vector.records),
            staleness: vector.staleness,
            resetAt: vector.resetAt,
            evaluatedAt: vector.evaluatedAt
        )
        #expect(result.currentPB?.id == vector.expectedCurrentId, "\(vector.id) current")
        #expect(result.lifetimePB?.id == vector.expectedLifetimeId, "\(vector.id) lifetime")
    }

    @Test(arguments: Fixtures.badges)
    func badgeVector(_ vector: PBBadgeVector) {
        let ids = PBDerivation.badgeIds(
            rule: PBDerivationVectorSupport.pbRule(from: vector.rule),
            records: PBDerivationVectorSupport.records(from: vector.records)
        )
        #expect(ids == vector.expectedBadgedIds, "\(vector.id) badges")
    }

    @Test(arguments: Fixtures.lifetimeVisibility)
    func lifetimeVisibilityVector(_ vector: PBLifetimeVisibilityVector) {
        let show = PBDerivation.shouldShowLifetimePB(
            lifetime: PBDerivationVectorSupport.visibilityRecord(
                from: vector.lifetime,
                id: "lifetime"
            ),
            current: PBDerivationVectorSupport.visibilityRecord(
                from: vector.current,
                id: "current"
            ),
            rule: PBDerivationVectorSupport.pbRule(from: vector.rule)
        )
        #expect(show == vector.expectedShow, "\(vector.id) show")
    }
}
#endif
