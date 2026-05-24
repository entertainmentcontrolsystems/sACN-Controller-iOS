import Foundation
import Combine

/// Main ViewModel for sACN Controller iOS.
/// Manages fixtures, DMX output, cues, and settings.
@MainActor
class SACNViewModel: ObservableObject {

    // ─── Dependencies ───────────────────────────────────────────────────────

    private let sacn = SACNSender()
    private let cueEngine = CueListEngine()
    private var sendTimer: Timer?

    // ─── Published State ────────────────────────────────────────────────────

    @Published var profiles: [FixtureProfile] = []
    @Published var fixtures: [FixtureInstance] = []
    @Published var looks: [Look] = []
    @Published var groups: [FixtureGroup] = []
    @Published var cueLists: [CueList] = []
    @Published var selectedFixtureId: String?
    @Published var multiSelectedIds = Set<String>()
    @Published var dmxValues: [String: [Int: Int]] = [:]
    @Published var sacnRunning = false
    @Published var blackoutActive = false
    @Published var cuePlayback = CueListEngine.PlaybackState()
    @Published var networkStatus = NetworkStatus()
    @Published var settings = AppSettings()
    @Published var converterConfig = ConverterConfig()
    @Published var converterRunning = false
    @Published var statusMessage: String?

    init() {
        sacn.open()
        startSendLoop()
    }

    deinit {
        sendTimer?.invalidate()
        Task { @MainActor in sacn.close() }
    }

    // ─── Send Loop ──────────────────────────────────────────────────────────

    private func startSendLoop() {
        sacnRunning = true
        sendTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendAllUniverses() }
        }
    }

    private func sendAllUniverses() {
        // Priority 1: Cue playback
        if cuePlayback.isPlaying && !cuePlayback.liveValues.isEmpty {
            sendDmxMap(cuePlayback.liveValues)
            return
        }

        // Priority 2: Blackout
        if blackoutActive {
            let unis = Set(fixtures.map(\.universe))
            for uni in unis {
                sacn.sendUniverse(uni, dmx: [UInt8](repeating: 0, count: 512))
            }
            return
        }

        // Priority 3: Manual
        sendDmxMap(dmxValues)
    }

    private func sendDmxMap(_ map: [String: [Int: Int]]) {
        var universeArrays: [Int: [UInt8]] = [:]
        for fixture in fixtures {
            guard let profile = profiles.first(where: { $0.id == fixture.profileId }),
                  let mode = profile.modes.first(where: { $0.name == profile.modes[safe: fixture.modeIndex]?.name }),
                  let values = map[fixture.id] else { continue }

            var array = universeArrays[fixture.universe] ?? [UInt8](repeating: 0, count: 512)
            for ch in mode.channels {
                let value = values[ch.offset] ?? ch.defaultValue
                let dmxAddr = fixture.startAddress + ch.offset - 2
                guard dmxAddr >= 0, dmxAddr < 512 else { continue }
                if ch.is16Bit {
                    array[dmxAddr] = UInt8((value >> 8) & 0xFF)
                    if let fineOffset = ch.fineOffset {
                        let fineAddr = fixture.startAddress + fineOffset - 2
                        if fineAddr >= 0, fineAddr < 512 {
                            array[fineAddr] = UInt8(value & 0xFF)
                        }
                    }
                } else {
                    array[dmxAddr] = UInt8(value & 0xFF)
                }
            }
            universeArrays[fixture.universe] = array
        }
        for (uni, dmx) in universeArrays {
            sacn.sendUniverse(uni, dmx: dmx)
        }
    }

    // ─── Blackout ───────────────────────────────────────────────────────────

    func toggleBlackout() {
        blackoutActive.toggle()
        statusMessage = blackoutActive ? "BLACKOUT" : "Output restored"
    }

    // ─── Fixture Actions ────────────────────────────────────────────────────

    func setChannelValue(fixtureId: String, offset: Int, value: Int) {
        var vals = dmxValues[fixtureId] ?? [:]
        vals[offset] = value
        dmxValues[fixtureId] = vals
    }

    func executeHome(fixtureId: String) {
        guard let fix = fixtures.first(where: { $0.id == fixtureId }),
              let prof = profiles.first(where: { $0.id == fix.profileId }),
              let mode = prof.modes.first(where: { modeMatches($0, index: fix.modeIndex, profile: prof) }) else { return }

        var vals = dmxValues[fixtureId] ?? [:]
        for ch in mode.channels {
            vals[ch.offset] = ch.homeValue > 0 ? ch.homeValue : ch.defaultValue
        }
        dmxValues[fixtureId] = vals
        statusMessage = "\(fix.name): Home"
    }

    // ─── Looks ──────────────────────────────────────────────────────────────

    func saveLook(_ name: String) {
        let look = Look(name: name, fixtureStates: dmxValues)
        looks.append(look)
        looks.sort { $0.timestamp > $1.timestamp }
        statusMessage = "Look \"\(name)\" saved"
    }

    func recallLook(_ lookId: String) {
        guard let look = looks.first(where: { $0.id == lookId }) else { return }
        dmxValues = look.fixtureStates
        statusMessage = "Look \"\(look.name)\" recalled"
    }

    // ─── Cue Lists ──────────────────────────────────────────────────────────

    func createCueList(_ name: String) {
        cueLists.append(CueList(name: name))
    }

    func playCueList(_ id: String) {
        guard let list = cueLists.first(where: { $0.id == id }) else { return }
        cueEngine.start(list: list) { [weak self] state in
            self?.cuePlayback = state
        }
        statusMessage = "Playing \"\(list.name)\""
    }

    func goNext() { cueEngine.go() }
    func goBack() { cueEngine.goBack() }
    func stopPlayback() { cueEngine.stop() }

    func saveCurrentAsCue(cueListId: String) {
        guard let idx = cueLists.firstIndex(where: { $0.id == cueListId }) else { return }
        var list = cueLists[idx]
        let nextNum = Float((list.steps.map(\.number).max() ?? 0) + 1)
        let step = CueStep(number: nextNum, label: "Cue \(Int(nextNum))", fixtureStates: dmxValues)
        list.steps.append(step)
        cueLists[idx] = list
        statusMessage = "Added cue \(Int(nextNum))"
    }

    // ─── Add Fixture ────────────────────────────────────────────────────────

    func addFixture(name: String, profileId: String, universe: Int, address: Int) {
        let fixture = FixtureInstance(
            name: name, profileId: profileId,
            universe: universe, startAddress: address
        )
        fixtures.append(fixture)
        dmxValues[fixture.id] = [:]
        statusMessage = "Added \(name) at \(universe):\(address)"
    }

    private func modeMatches(_ mode: DMXMode, index: Int, profile: FixtureProfile) -> Bool {
        profile.modes.firstIndex(where: { $0.id == mode.id }) == index
    }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
