import Foundation
import Network
import SwiftAgentCore

/// Zero-config discovery of SwiftAgent servers on the local device and LAN.
///
/// `AgentServiceBrowser` wraps `NWBrowser` to discover any service
/// advertised as ``NetworkServerTransport/bonjourServiceType``
/// (`_appmcp._tcp`). It surfaces an `AsyncStream` of change events so
/// callers can build reactive UIs or poll for a first match.
///
/// ### Permissions on Apple platforms
///
/// Bonjour browsing requires:
///
/// - `NSLocalNetworkUsageDescription` — the user-facing reason shown
///   in the system permission prompt.
/// - `NSBonjourServices` — must include `"_appmcp._tcp"`.
///
/// Apps that forget either key will see an immediate browser failure
/// at runtime, not a permission prompt.
public final class AgentServiceBrowser: @unchecked Sendable {
    /// A single discovered SwiftAgent server.
    public struct DiscoveredService: Sendable, Hashable {
        /// Bonjour service name (usually the app's display name).
        public let name: String
        /// The underlying endpoint, suitable for ``NetworkClientTransport``.
        public let endpoint: NWEndpoint
        /// TXT-record metadata advertised by the server.
        public let txtRecord: [String: String]
    }

    /// An event emitted on the discovery stream.
    public enum Event: Sendable {
        /// A new service appeared.
        case appeared(DiscoveredService)
        /// A previously-appeared service disappeared.
        case disappeared(DiscoveredService)
        /// The browser failed and will no longer emit events.
        case failed(String)
    }

    private let queue = DispatchQueue(label: "app.mcp.client.browser")
    private var browser: NWBrowser?

    /// Build a new browser. Discovery is lazy — call ``events()`` to
    /// begin browsing.
    public init() {}

    /// Start browsing and receive events as they arrive.
    ///
    /// - Returns: An `AsyncStream` of discovery events. Stops when the
    ///   browser is released or ``stop()`` is called.
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
                type: AgentBonjour.serviceType,
                domain: nil
            )
            let browser = NWBrowser(for: descriptor, using: parameters)
            self.browser = browser

            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }

            browser.browseResultsChangedHandler = { results, changes in
                for change in changes {
                    switch change {
                    case .added(let result):
                        if let service = Self.describe(result) {
                            continuation.yield(.appeared(service))
                        }
                    case .removed(let result):
                        if let service = Self.describe(result) {
                            continuation.yield(.disappeared(service))
                        }
                    default:
                        break
                    }
                }
                _ = results
            }

            continuation.onTermination = { @Sendable _ in
                browser.cancel()
            }

            browser.start(queue: queue)
        }
    }

    /// Stop browsing. Safe to call multiple times.
    public func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Convert an `NWBrowser.Result` into the SwiftAgent-friendly
    /// ``DiscoveredService`` shape, extracting the name and TXT record.
    private static func describe(_ result: NWBrowser.Result) -> DiscoveredService? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata {
            for (key, entry) in record {
                if case .string(let stringValue) = entry {
                    txt[key] = stringValue
                }
            }
        }
        return DiscoveredService(
            name: name,
            endpoint: result.endpoint,
            txtRecord: txt
        )
    }
}
