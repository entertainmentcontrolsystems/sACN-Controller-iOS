import Foundation
import Network
import Combine

/// sACN (ANSI E1.31) DMX sender using Network framework.
///
/// Swift-native multicast sender — no external dependencies.
/// Mirrors the Android SACNSender API surface from sacn-common.
@MainActor
class SACNSender: ObservableObject {

    // ─── Config ─────────────────────────────────────────────────────────────

    @Published var sourceName = "ECS Lighting"
    @Published var priority = 100
    @Published var isOpen = false
    @Published var sendErrorCount = 0

    // ─── Constants ──────────────────────────────────────────────────────────

    private static let sacnPort: UInt16 = 5568
    private static let dmxSlots = 512

    private static let acnID: [UInt8] = [
        0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31,
        0x37, 0x00, 0x00, 0x00
    ]

    // ─── State ──────────────────────────────────────────────────────────────

    private var connections: [Int: NWConnection] = [:]  // universe → connection
    private let cid = (0..<16).map { _ in UInt8.random(in: 0...255) }
    private var sequenceNumbers: [Int: UInt8] = [:]

    // ─── Lifecycle ──────────────────────────────────────────────────────────

    func open() {
        isOpen = true
        sendErrorCount = 0
    }

    func close() {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        isOpen = false
    }

    // ─── Send ───────────────────────────────────────────────────────────────

    /// Send DMX values for a universe.
    func sendUniverse(_ universe: Int, dmx: [UInt8]) {
        guard isOpen else { return }

        let seq = ((sequenceNumbers[universe] ?? 0) &+ 1) & 0xFF
        sequenceNumbers[universe] = seq

        let packet = buildPacket(universe: universe, dmx: dmx, seq: seq)

        let conn = getOrCreateConnection(universe: universe)
        conn.send(content: Data(packet), completion: .contentProcessed { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.sendErrorCount += 1 }
            }
        })
    }

    /// Convenience: send a sparse channel map.
    func sendChannels(_ universe: Int, channels: [Int: UInt8]) {
        var dmx = [UInt8](repeating: 0, count: Self.dmxSlots)
        for (ch, val) in channels {
            dmx[(ch - 1).clamped(to: 0...Self.dmxSlots - 1)] = val
        }
        sendUniverse(universe, dmx: dmx)
    }

    // ─── Packet Building ────────────────────────────────────────────────────

    private func buildPacket(universe: Int, dmx: [UInt8], seq: UInt8) -> [UInt8] {
        let totalLen = 126 + Self.dmxSlots
        var buf = [UInt8](repeating: 0, count: totalLen)

        // Preamble
        buf[0] = 0x00; buf[1] = 0x10      // Preamble Length
        buf[2] = 0x00; buf[3] = 0x00      // Postamble Length
        for i in 0..<12 { buf[4 + i] = Self.acnID[i] } // ACN Packet Identifier

        // Root PDU
        let rootLen = UInt16(totalLen - 16)
        buf[16] = UInt8(0x70 | ((rootLen >> 8) & 0x0F))
        buf[17] = UInt8(rootLen & 0xFF)
        buf[18] = 0x00; buf[19] = 0x00; buf[20] = 0x00; buf[21] = 0x04 // VECTOR_ROOT_E131_DATA
        for i in 0..<16 { buf[22 + i] = cid[i] }

        // Framing PDU
        let framingLen = UInt16(totalLen - 38)
        buf[38] = UInt8(0x70 | ((framingLen >> 8) & 0x0F))
        buf[39] = UInt8(framingLen & 0xFF)
        buf[40] = 0x00; buf[41] = 0x00; buf[42] = 0x00; buf[43] = 0x02 // VECTOR_E131_DATA_PACKET

        // Source Name (64 bytes)
        let srcBytes = Array(sourceName.utf8)
        for i in 0..<64 { buf[44 + i] = i < srcBytes.count ? srcBytes[i] : 0 }

        buf[108] = UInt8(priority.clamped(to: 0...200))
        buf[109] = 0x00; buf[110] = 0x00   // Sync Address
        buf[111] = seq                       // Sequence Number
        buf[112] = 0x00                      // Options
        buf[113] = UInt8((universe >> 8) & 0xFF)
        buf[114] = UInt8(universe & 0xFF)

        // DMP Layer
        let dmpLen = UInt16(totalLen - 115)
        buf[115] = UInt8(0x70 | ((dmpLen >> 8) & 0x0F))
        buf[116] = UInt8(dmpLen & 0xFF)
        buf[117] = 0x02                      // VECTOR_DMP_SET_PROPERTY
        buf[118] = 0xA1                      // Address & Data Type
        buf[119] = 0x00; buf[120] = 0x00    // First Property Address
        buf[121] = 0x00; buf[122] = 0x01    // Address Increment
        buf[123] = 0x02; buf[124] = 0x01    // Property Count (513 = start code + 512)
        buf[125] = 0x00                      // DMX Start Code

        // DMX values
        for i in 0..<min(dmx.count, Self.dmxSlots) {
            buf[126 + i] = dmx[i]
        }

        return buf
    }

    // ─── Connection Management ──────────────────────────────────────────────

    private func getOrCreateConnection(universe: Int) -> NWConnection {
        if let existing = connections[universe], existing.state == .ready {
            return existing
        }

        let host = NWEndpoint.Host(Self.universeToMulticast(universe))
        let port = NWEndpoint.Port(rawValue: Self.sacnPort)!
        let conn = NWConnection(host: host, port: port, using: .udp)
        connections[universe] = conn

        conn.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            if case .failed = state {
                Task { @MainActor in self?.connections.removeValue(forKey: universe) }
            }
        }
        conn.start(queue: DispatchQueue.global(qos: .utility))
        return conn
    }

    // ─── Addressing ─────────────────────────────────────────────────────────

    static func universeToMulticast(_ universe: Int) -> String {
        let hi = (universe >> 8) & 0xFF
        let lo = universe & 0xFF
        return "239.255.\(hi).\(lo)"
    }
}

// MARK: - Helpers

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
