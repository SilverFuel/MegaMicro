import Foundation
import Network
import Security
import SwiftUI

/// Discovers MegaMicro Macs on the LAN (Bonjour), pairs with one, and keeps a
/// live WebSocket that streams `DashboardSnapshot`s into `dashboard` and sends
/// `SyncCommand`s back. iOS/watchOS side of the sync protocol.
@Observable @MainActor
final class SyncClient {
    enum Phase: Equatable {
        case browsing
        case connecting
        case needsPairing          // discovered but no stored token
        case connected
        case failed(String)
    }

    struct Discovered: Identifiable, Hashable {
        let id: String             // Bonjour instance id (from TXT)
        let name: String           // device name (from TXT)
        let endpoint: NWEndpoint
    }

    let dashboard = DashboardModel()
    var phase: Phase = .browsing
    var discovered: [Discovered] = []
    private(set) var connectedName: String?

    private let clientName: String
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var current: Discovered?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(clientName: String) {
        self.clientName = clientName
        dashboard.onCommand = { [weak self] command in self?.send(.command(command)) }
        dashboard.startClientRendering()  // re-derive LED glows locally
        WatchBridge.shared.activate()     // relay snapshots to a paired Watch
    }

    // MARK: Stored tokens (one per paired Mac)

    private func storedToken(_ id: String) -> String? {
        if let token = TokenKeychain.token(for: id) { return token }
        // Migrate any token left in UserDefaults by earlier builds, then drop it.
        let legacyKey = "megamicro.token.\(id)"
        if let legacy = UserDefaults.standard.string(forKey: legacyKey) {
            TokenKeychain.set(legacy, for: id)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return legacy
        }
        return nil
    }
    private func store(token: String, for id: String) { TokenKeychain.set(token, for: id) }
    func hasPairing(for d: Discovered) -> Bool { storedToken(d.id) != nil }

    // MARK: Discovery

    func startBrowsing() {
        phase = .browsing
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: SyncBonjour.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updateResults(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func updateResults(_ results: Set<NWBrowser.Result>) {
        discovered = results.compactMap { result in
            guard case let .bonjour(txt) = result.metadata else {
                return Discovered(id: UUID().uuidString, name: "MegaMicro", endpoint: result.endpoint)
            }
            let id = txt[SyncBonjour.txtInstanceID] ?? UUID().uuidString
            let name = txt[SyncBonjour.txtDeviceName] ?? "MegaMicro"
            return Discovered(id: id, name: name, endpoint: result.endpoint)
        }
        .sorted { $0.name < $1.name }

        // Auto-connect to an already-paired Mac so the board appears without a tap.
        if case .browsing = phase, let paired = discovered.first(where: hasPairing) {
            connect(to: paired)
        }
    }

    // MARK: Connect / pair

    /// Connect using the stored token if paired; otherwise the caller supplies
    /// the 6-digit pairing code shown on the Mac.
    func connect(to d: Discovered, pairingCode: String? = nil) {
        current = d
        let secret = pairingCode ?? storedToken(d.id)
        guard let secret else { phase = .needsPairing; return }
        phase = .connecting
        connection?.cancel()

        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        let connection = NWConnection(to: d.endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleState(state, secret: secret, deviceID: d.id) }
        }
        connection.start(queue: .main)
        self.connection = connection
        receive()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connectedName = nil
        phase = .browsing
    }

    private func handleState(_ state: NWConnection.State, secret: String, deviceID: String) {
        switch state {
        case .ready:
            send(.hello(SyncHello(secret: secret, clientName: clientName)))
        case .failed(let error):
            phase = .failed(error.localizedDescription)
        case .cancelled:
            if case .connected = phase { phase = .browsing }
        default:
            break
        }
    }

    // MARK: WebSocket I/O

    private func send(_ message: ClientMessage) {
        guard let connection, let data = try? encoder.encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor in self.handleServerData(data) }
            }
            if error == nil { self.receive() }
        }
    }

    private func handleServerData(_ data: Data) {
        guard let message = try? decoder.decode(ServerMessage.self, from: data) else { return }
        switch message {
        case .snapshot(let snapshot):
            dashboard.apply(snapshot)
            connectedName = snapshot.deviceName
            phase = .connected
            if let json = try? encoder.encode(snapshot) {
                WatchBridge.shared.send(snapshotJSON: json)
            }
        case .paired(let token):
            if let id = current?.id { store(token: token, for: id) }
        case .rejected(let reason):
            phase = .failed("Pairing rejected: \(reason)")
        }
    }
}

/// Keychain-backed storage for per-Mac pairing tokens. These are bearer
/// secrets that grant command access to a Mac, so they live in the Keychain
/// rather than UserDefaults. Keyed by the Mac's Bonjour instance id.
private enum TokenKeychain {
    private static let service = "com.jessewaites.megamicro.pairing"

    static func token(for id: String) -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ token: String, for id: String) {
        let data = Data(token.utf8)
        let query = baseQuery(id)
        if SecItemUpdate(query as CFDictionary,
                         [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func baseQuery(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id]
    }
}
