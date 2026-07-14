import Foundation

/// JWT minted by the token broker after a successful connect.
struct BrokerSession: Equatable, Sendable {
    let token: String
    let expiresAt: Date?
}
