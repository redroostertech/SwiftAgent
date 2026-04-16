import Foundation
import Network
import SwiftAgentCore

/// TCP + Bonjour server transport for SwiftAgent.
///
/// `NetworkServerTransport` hosts the server on a local `NWListener`,
/// advertises the service over Bonjour so clients can find it with no
/// manual address configuration, and speaks the standard SwiftAgent wire
/// format: newline-delimited JSON-RPC, one message per line.
///
/// ### Where it fits best
///
/// This transport is the **primary path on macOS** and a
/// **foreground-only path on iOS**. The distinction is a consequence of
/// the sandbox:
///
/// - On macOS, apps run as real long-lived processes. The listener stays
///   up for as long as the app stays open, and Bonjour advertisement is
///   persistent. This is the right transport for macOS menu-bar apps,
///   document apps, and helper daemons that want to expose tools to any
///   MCP-compatible agent on the local machine or LAN.
/// - On iOS and iPadOS, the OS aggressively suspends backgrounded apps.
///   The listener therefore only accepts connections while the app is
///   foregrounded (plus a short grace period on backgrounding). This
///   transport still makes sense when the SwiftAgent-consuming app is
///   already the focus — for example, an "expose my current document
///   to the agent running on my Mac" flow — but it is **not** the right
///   path for "agent reaches into app B while app A is foregrounded"
///   scenarios. Use the App Intents bridge in the `SwiftAgentIntents` module
///   for that.
///
/// ### Permissions
///
/// On iOS 14+, the first use of local networking triggers the system
/// "allow local network access" dialog. Apps that ship this transport
/// must add the keys listed in the package README (``NSLocalNetworkUsageDescription``
/// and ``NSBonjourServices``) to their `Info.plist`.
public final class NetworkServerTransport: AgentServerTransport, @unchecked Sendable {
    /// The Bonjour service type SwiftAgent advertises. Forwarded from
    /// ``AgentBonjour/serviceType`` for call-site brevity.
    public static let bonjourServiceType = AgentBonjour.serviceType

    /// Configuration knobs for the network transport.
    public struct Configuration: Sendable {
        /// Bonjour display name. Defaults to the bundle display name, or
        /// `SwiftAgent` when no bundle is available (e.g. command-line tools).
        public var serviceName: String
        /// Port to bind on. Use `.any` to let the OS pick an ephemeral port.
        public var port: NWEndpoint.Port
        /// Additional TXT-record entries advertised alongside the service.
        /// Typical use: `"name"`, `"bundle"`, `"version"`.
        public var txtRecord: [String: String]

        /// Build a configuration with the supplied values.
        public init(
            serviceName: String,
            port: NWEndpoint.Port = .any,
            txtRecord: [String: String] = [:]
        ) {
            self.serviceName = serviceName
            self.port = port
            self.txtRecord = txtRecord
        }

        /// Convenience factory that builds a sensible default configuration
        /// from the main bundle and a server ``MCPImplementation``.
        public static func `default`(info: MCPImplementation) -> Configuration {
            var txt: [String: String] = [
                "v": AgentProtocol.version,
                "name": info.name,
                "version": info.version
            ]
            if let bundle = info.bundleIdentifier {
                txt["bundle"] = bundle
            }
            return Configuration(
                serviceName: info.name,
                port: .any,
                txtRecord: txt
            )
        }
    }

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "app.mcp.server.network")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var handler: RequestHandler?

    /// Build a network transport with the given configuration.
    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func start(handler: @escaping RequestHandler) async throws {
        self.handler = handler

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: configuration.port)
        } catch {
            throw MCPError.custom(
                code: -32020,
                message: "Failed to open NWListener: \(error.localizedDescription)"
            )
        }

        let txt = NWTXTRecord(configuration.txtRecord)
        listener.service = NWListener.Service(
            name: configuration.serviceName,
            type: Self.bonjourServiceType,
            domain: nil,
            txtRecord: txt
        )

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() async {
        queue.sync {
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.handler = nil
        }
    }

    // MARK: - Connection handling

    /// Accept a new connection, store it, wire the state handler, and
    /// begin the per-connection read loop.
    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.beginReading(connection)
            case .failed, .cancelled:
                self.queue.async {
                    self.connections.removeValue(forKey: ObjectIdentifier(connection))
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Begin a non-blocking read loop on a ready connection, one
    /// newline-delimited message at a time.
    private func beginReading(_ connection: NWConnection) {
        let reader = LineReader(connection: connection, queue: queue) { [weak self] line in
            guard let self else { return }
            await self.dispatch(line: line, on: connection)
        }
        reader.resume()
    }

    /// Parse a single JSON-RPC message, hand it to the server, and write
    /// the response (if any) back on the same connection.
    private func dispatch(line: Data, on connection: NWConnection) async {
        guard let handler else { return }
        do {
            let request = try JSONDecoder.swiftAgent.decode(JSONRPCRequest.self, from: line)
            if let response = await handler(request) {
                let payload = try JSONRPCFraming.encode(response)
                connection.send(content: payload, completion: .idempotent)
            }
        } catch {
            let error = JSONRPCError.parseError(error.localizedDescription)
            let response = JSONRPCResponse(id: nil, error: error)
            if let payload = try? JSONRPCFraming.encode(response) {
                connection.send(content: payload, completion: .idempotent)
            }
        }
    }
}
