import Foundation

/// Shared data models for sACN Controller iOS.
/// Mirrors the Android Models.kt structure.

// ─── Channel Definition ─────────────────────────────────────────────────────

enum ChannelCategory: String, Codable {
    case intensity, color, position, gobo, beam, other
}

struct ChannelDef: Identifiable, Codable {
    var id: String { "\(offset)" }
    let name: String
    let displayName: String
    let offset: Int
    let fineOffset: Int?
    let defaultValue: Int
    let category: ChannelCategory
    let homeValue: Int

    var is16Bit: Bool { fineOffset != nil }
    var maxValue: Int { is16Bit ? 65535 : 255 }
}

// ─── DMX Mode ───────────────────────────────────────────────────────────────

struct DMXMode: Identifiable, Codable {
    var id: String { name }
    let name: String
    let channels: [ChannelDef]
    let footprint: Int
}

// ─── Fixture Profile ────────────────────────────────────────────────────────

struct FixtureProfile: Identifiable, Codable {
    let id: String
    let manufacturer: String
    let name: String
    let modes: [DMXMode]
    var gdtfFileName: String = ""

    init(id: String = UUID().uuidString, manufacturer: String,
         name: String, modes: [DMXMode], gdtfFileName: String = "") {
        self.id = id; self.manufacturer = manufacturer
        self.name = name; self.modes = modes
        self.gdtfFileName = gdtfFileName
    }
}

// ─── Fixture Instance ───────────────────────────────────────────────────────

struct FixtureInstance: Identifiable, Codable {
    let id: String
    let name: String
    let profileId: String
    let modeIndex: Int
    let universe: Int
    let startAddress: Int

    init(id: String = UUID().uuidString, name: String,
         profileId: String, modeIndex: Int = 0,
         universe: Int = 1, startAddress: Int = 1) {
        self.id = id; self.name = name; self.profileId = profileId
        self.modeIndex = modeIndex; self.universe = universe
        self.startAddress = startAddress
    }
}

// ─── Look ───────────────────────────────────────────────────────────────────

struct Look: Identifiable, Codable {
    let id: String
    let name: String
    let timestamp: Date
    let fixtureStates: [String: [Int: Int]]  // fixtureId → (offset → value)
    let tags: [String]

    init(id: String = UUID().uuidString, name: String,
         fixtureStates: [String: [Int: Int]] = [:],
         tags: [String] = [], timestamp: Date = Date()) {
        self.id = id; self.name = name; self.fixtureStates = fixtureStates
        self.tags = tags; self.timestamp = timestamp
    }
}

// ─── Cue List ───────────────────────────────────────────────────────────────

enum CueWaitType: String, Codable { case manual, timed }

struct CueStep: Identifiable, Codable {
    let id: String
    let number: Float
    let label: String
    let fadeInMs: TimeInterval
    let delayMs: TimeInterval
    let waitType: CueWaitType
    let waitTimeMs: TimeInterval
    let fixtureStates: [String: [Int: Int]]

    init(id: String = UUID().uuidString, number: Float,
         label: String = "", fadeInMs: TimeInterval = 2.0,
         delayMs: TimeInterval = 0, waitType: CueWaitType = .manual,
         waitTimeMs: TimeInterval = 0,
         fixtureStates: [String: [Int: Int]] = [:]) {
        self.id = id; self.number = number; self.label = label
        self.fadeInMs = fadeInMs; self.delayMs = delayMs
        self.waitType = waitType; self.waitTimeMs = waitTimeMs
        self.fixtureStates = fixtureStates
    }
}

struct CueList: Identifiable, Codable {
    let id: String
    let name: String
    var steps: [CueStep]
    var currentStepIndex: Int = -1
    var isRunning: Bool = false

    init(id: String = UUID().uuidString, name: String, steps: [CueStep] = []) {
        self.id = id; self.name = name; self.steps = steps
    }
}

// ─── Fixture Group ──────────────────────────────────────────────────────────

struct FixtureGroup: Identifiable, Codable {
    let id: String
    let name: String
    let fixtureIds: [String]
    let color: Int

    init(id: String = UUID().uuidString, name: String,
         fixtureIds: [String] = [], color: Int = 0xFF4D9EFF) {
        self.id = id; self.name = name
        self.fixtureIds = fixtureIds; self.color = color
    }
}

// ─── Converter Config ───────────────────────────────────────────────────────

struct ConverterConfig: Codable {
    var enabled = false
    var inputUniverse = 1
    var inputStartAddr = 1
    var outputFixtureId = ""
}

// ─── Network Status ─────────────────────────────────────────────────────────

struct NetworkStatus {
    var ssid = ""
    var wifiConnected = false
    var sendErrors = 0
}

// ─── App Settings ───────────────────────────────────────────────────────────

struct AppSettings: Codable {
    var sourceName = "sACN Controller"
    var sacnPriority = 100
    var bindIp = ""
}
