import Foundation

/// Why the board / progression has no *current* PB (#28 empty-state copy).
enum CurrentPBEmptyReason: Equatable, Sendable {
    /// No sets and no manual entries for this exercise (sessionDerived leftovers ignored).
    case neverTrained
    /// Active reset with no post-reset current PB.
    case reset
    /// Had dated history that is no longer fresh under staleness.
    case lapsed
    /// Has history but neither reset nor a clear lapse (e.g. undated-only lifetime).
    case noCurrent
}

enum CurrentPBEmptyCopy {
    /// Board caption (short).
    static func boardCaption(for reason: CurrentPBEmptyReason) -> String {
        switch reason {
        case .neverTrained: return "No PB yet"
        case .reset: return "Reset"
        case .lapsed: return "Lapsed"
        case .noCurrent: return "No current PB"
        }
    }

    /// Progression hero title when current is absent.
    static func progressionTitle(for reason: CurrentPBEmptyReason) -> String {
        switch reason {
        case .neverTrained: return "No PB yet"
        case .reset, .lapsed, .noCurrent: return "No current PB"
        }
    }

    /// Progression supporting line under the hero title.
    static func progressionDetail(for reason: CurrentPBEmptyReason) -> String? {
        switch reason {
        case .neverTrained:
            return "Log a set to establish your first PB."
        case .reset:
            return "You reset this lift — log a set when you're ready."
        case .lapsed:
            return "Your last best has lapsed."
        case .noCurrent:
            return nil
        }
    }

    static func reason(
        hasHistory: Bool,
        hasActiveReset: Bool,
        stalenessEnabled: Bool
    ) -> CurrentPBEmptyReason {
        guard hasHistory else { return .neverTrained }
        if hasActiveReset { return .reset }
        if stalenessEnabled { return .lapsed }
        return .noCurrent
    }
}
