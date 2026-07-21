import Foundation
import Security

/// The Mac's LAN pairing secret. A single shared token per machine: any client
/// that presents it (learned via the QR/code shown during pairing) is trusted
/// to send commands. Stored owner-only (0600) via `PrivateFileStore`. Regenerate
/// to revoke every paired device at once.
enum PairingStore {
    private static var tokenURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MegaMicro/pairing-token")
    }

    private static var instanceURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MegaMicro/instance-id")
    }

    /// Stable id for this Mac's MegaMicro install (Bonjour TXT), so a phone can
    /// tell two machines apart even if they share a device name.
    static func instanceID() -> String {
        if let data = try? Data(contentsOf: instanceURL),
           let id = String(data: data, encoding: .utf8), !id.isEmpty {
            return id
        }
        let id = UUID().uuidString
        try? PrivateFileStore.write(Data(id.utf8), to: instanceURL)
        return id
    }

    /// The current token, generating and persisting one on first use.
    static func currentToken() -> String {
        if let data = try? Data(contentsOf: tokenURL),
           let token = String(data: data, encoding: .utf8), !token.isEmpty {
            return token
        }
        return regenerate()
    }

    /// Mint a fresh token (revokes all existing pairings).
    @discardableResult
    static func regenerate() -> String {
        let token = randomToken()
        try? PrivateFileStore.write(Data(token.utf8), to: tokenURL)
        return token
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Trapping beats silently emitting an all-zero (guessable) token.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes).base64EncodedString()
    }
}
