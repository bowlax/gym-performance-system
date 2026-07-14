import Foundation

enum JWTClaimsDecoder {
    struct Claims: Equatable, Sendable {
        let memberId: UUID
        let gymId: UUID
    }

    /// Decodes `member_id` and `gym_id` from a broker JWT payload (no signature verification).
    static func decodeMemberAndGym(from token: String) throws -> Claims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw SyncError.invalidBrokerToken("JWT must have three segments")
        }

        let payloadData = try decodeBase64URL(String(parts[1]))
        let object = try JSONSerialization.jsonObject(with: payloadData)
        guard let payload = object as? [String: Any] else {
            throw SyncError.invalidBrokerToken("JWT payload is not a JSON object")
        }

        guard let memberIdString = payload["member_id"] as? String,
              let memberId = UUID(uuidString: memberIdString) else {
            throw SyncError.invalidBrokerToken("JWT missing member_id claim")
        }

        guard let gymIdString = payload["gym_id"] as? String,
              let gymId = UUID(uuidString: gymIdString) else {
            throw SyncError.invalidBrokerToken("JWT missing gym_id claim")
        }

        return Claims(memberId: memberId, gymId: gymId)
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw SyncError.invalidBrokerToken("JWT payload is not valid base64")
        }
        return data
    }
}
