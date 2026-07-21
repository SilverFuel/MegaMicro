import Foundation
import Network
import Security

/// LAN sync server: advertises MegaMicro over Bonjour, accepts WebSocket
/// clients (iPhone/Watch-via-phone), authenticates them with the pairing
/// secret, streams `DashboardSnapshot`s, and forwards `SyncCommand`s back.
///
/// Distinct from `WebhookServer` (loopback, agent ingestion): this one binds
/// the LAN and is gated by a shared token, so it never widens the webhook's
/// localhost-trust boundary.
final class SyncServer: @unchecked Sendable {
    /// Fixed LAN port; Bonjour advertises it so clients never hardcode it.
    static let port: UInt16 = 48803
    private static let maximumConnections = 16
    private static let authTimeout: TimeInterval = 8
    private static let pairingWindow: TimeInterval = 120
    /// Wrong codes invalidate the window after this many tries, so a LAN
    /// attacker can't churn connections to brute-force the 6-digit code.
    private static let pairingMaxAttempts = 5

    let deviceName: String
    let instanceID: String
    /// Returns the current long-lived token (generated on first use).
    private let tokenProvider: @Sendable () -> String
    /// Called on the server queue with a validated command; wiring hops to main.
    var onCommand: (@Sendable (SyncCommand) -> Void)?

    private let queue = DispatchQueue(label: "megamicro.sync")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var lastSnapshot: Data?
    private var pairingCode: String?
    private var pairingExpiry: Date?
    private var pairingAttempts = 0

    private(set) var isRunning = false

    private final class Client {
        let connection: NWConnection
        var authed = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    init(deviceName: String, instanceID: String, tokenProvider: @escaping @Sendable () -> String) {
        self.deviceName = deviceName
        self.instanceID = instanceID
        self.tokenProvider = tokenProvider
    }

    // MARK: Lifecycle

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
        var txt = NWTXTRecord()
        txt[SyncBonjour.txtInstanceID] = instanceID
        txt[SyncBonjour.txtDeviceName] = deviceName
        listener.service = NWListener.Service(
            name: deviceName, type: SyncBonjour.serviceType, txtRecord: txt)

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async { self.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
        isRunning = true
    }

    func stop() {
        queue.async {
            for client in self.clients.values { client.connection.cancel() }
            self.clients.removeAll()
        }
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: Pairing

    /// Open a pairing window and return the 6-digit code to display. A client
    /// that presents this code within the window is issued the long-lived token.
    func beginPairing() -> String {
        var bytes = [UInt8](repeating: 0, count: 3)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        let value = (Int(bytes[0]) << 16 | Int(bytes[1]) << 8 | Int(bytes[2])) % 1_000_000
        let code = String(format: "%06d", value)
        queue.async {
            self.pairingCode = code
            self.pairingExpiry = Date().addingTimeInterval(Self.pairingWindow)
            self.pairingAttempts = 0
        }
        return code
    }

    // MARK: Broadcast

    /// Push a snapshot to every authenticated client. `envelope` is an
    /// already-encoded `ServerMessage.snapshot(...)` (the caller owns building
    /// it on the main actor). Cheap no-op when the bytes are unchanged; the
    /// latest is cached and sent to any client that authenticates later.
    func broadcast(snapshotEnvelope envelope: Data) {
        queue.async {
            guard envelope != self.lastSnapshot else { return }
            self.lastSnapshot = envelope
            for client in self.clients.values where client.authed {
                self.send(envelope, on: client.connection)
            }
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        guard clients.count < Self.maximumConnections else {
            connection.cancel()
            return
        }
        let client = Client(connection)
        let id = ObjectIdentifier(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async { self?.clients[id] = nil }
            default: break
            }
        }
        connection.start(queue: queue)
        // Drop clients that never authenticate.
        queue.asyncAfter(deadline: .now() + Self.authTimeout) { [weak self] in
            guard let self, let client = self.clients[id], !client.authed else { return }
            connection.cancel()
            self.clients[id] = nil
        }
        receive(on: connection, id: id)
    }

    private func receive(on connection: NWConnection, id: ObjectIdentifier) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error != nil { connection.cancel(); return }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {
                connection.cancel()
                return
            }
            if let data, !data.isEmpty { self.handle(data, id: id) }
            self.receive(on: connection, id: id)
        }
    }

    private func handle(_ data: Data, id: ObjectIdentifier) {
        guard let client = clients[id],
              let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else { return }
        switch message {
        case .hello(let hello):
            authenticate(hello, client: client)
        case .command(let command):
            guard client.authed else { return }
            onCommand?(command)
        }
    }

    private func authenticate(_ hello: SyncHello, client: Client) {
        let token = tokenProvider()
        if hello.secret == token {
            client.authed = true
        } else if let code = pairingCode, let expiry = pairingExpiry, Date() < expiry {
            if hello.secret == code {
                client.authed = true
                clearPairing()  // one-shot
                send(envelope(.paired(token: token)), on: client.connection)
            } else {
                // Count failures server-side (across reconnects) and burn the
                // window once too many wrong codes arrive.
                pairingAttempts += 1
                if pairingAttempts >= Self.pairingMaxAttempts { clearPairing() }
                reject(client)
                return
            }
        } else {
            reject(client)
            return
        }
        // Immediately hand the newly-authed client the latest state.
        if let snapshot = lastSnapshot {
            send(snapshot, on: client.connection)
        }
    }

    private func reject(_ client: Client) {
        send(envelope(.rejected(reason: "not paired")), on: client.connection)
        client.connection.cancel()
    }

    private func clearPairing() {
        pairingCode = nil
        pairingExpiry = nil
        pairingAttempts = 0
    }

    // MARK: WebSocket send

    private func envelope(_ message: ServerMessage) -> Data {
        (try? JSONEncoder().encode(message)) ?? Data()
    }

    private func send(_ data: Data, on connection: NWConnection) {
        guard !data.isEmpty else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
    }
}
