import Foundation
import Network

/// Fires a single app-level UDP datagram at the LAN gateway.
/// macOS gates local-network access behind a TCC prompt; the ping/arp
/// subprocesses alone don't trigger it — an in-process socket does.
enum LANNudge {
    static func send() {
        guard let iface = NetUtil.primaryInterface() else { return }
        let octets = iface.ip.split(separator: ".")
        guard octets.count == 4 else { return }
        let gw = octets.dropLast().joined(separator: ".") + ".1"
        let conn = NWConnection(host: NWEndpoint.Host(gw), port: 9, using: .udp)
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
        conn.start(queue: DispatchQueue.global(qos: .utility))
        conn.send(content: Data([0x00]), completion: .contentProcessed { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { conn.cancel() }
        })
    }
}
