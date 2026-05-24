import Foundation

/// Cue List crossfade engine — iOS port of the Android CueListEngine.
///
/// Supports:
/// - Delay before fade
/// - Smoothstep crossfades between cues
/// - Timed auto-GO and manual wait
/// - Configurable back-time for reverse playback
class CueListEngine {

    struct PlaybackState {
        var cueListId: String?
        var cueListName = ""
        var currentStepIndex = -1
        var currentCue: CueStep?
        var isPlaying = false
        var isFading = false
        var fadeProgress: Float = 0
        var totalSteps = 0
        var liveValues: [String: [Int: Int]] = [:]
    }

    private var list: CueList?
    private var fadeSource: [String: [Int: Int]] = [:]
    private var workItem: DispatchWorkItem?
    private var fadeWorkItem: DispatchWorkItem?
    private var onStateUpdate: ((PlaybackState) -> Void)?

    // ─── Public API ─────────────────────────────────────────────────────────

    func start(list: CueList, onUpdate: @escaping (PlaybackState) -> Void) {
        stop()
        self.list = list
        self.onStateUpdate = onUpdate
        fadeSource = [:]

        if !list.steps.isEmpty {
            goNext()
        }
    }

    func stop() {
        workItem?.cancel()
        fadeWorkItem?.cancel()
        workItem = nil; fadeWorkItem = nil
        fadeSource = [:]
        notify(PlaybackState())
    }

    func go() { goNext() }

    func goBack(fadeTime: TimeInterval = 0) {
        guard let list = self.list else { return }
        fadeWorkItem?.cancel()
        workItem?.cancel()

        let prevIdx = max(list.currentStepIndex - 1, -1)
        let prevCue = prevIdx >= 0 ? list.steps[prevIdx] : nil

        if fadeTime <= 0 || prevCue == nil {
            // Snap
            self.list?.currentStepIndex = prevIdx
            notify(PlaybackState(
                cueListId: list.id, cueListName: list.name,
                currentStepIndex: prevIdx, currentCue: prevCue,
                totalSteps: list.steps.count,
                liveValues: prevCue?.fixtureStates ?? [:], isPlaying: true
            ))
        } else {
            // Fade back
            let currentVals = fadeSource
            fadeSource = currentVals.isEmpty ? (prevCue?.fixtureStates ?? [:]) : currentVals
            notify(PlaybackState(
                cueListId: list.id, cueListName: list.name,
                currentStepIndex: prevIdx, currentCue: prevCue,
                totalSteps: list.steps.count,
                liveValues: fadeSource, isPlaying: true
            ))
            executeCrossfade(from: fadeSource, to: prevCue!.fixtureStates,
                             duration: fadeTime, stepIdx: prevIdx)
        }
    }

    // ─── Internal ───────────────────────────────────────────────────────────

    private func goNext() {
        guard var list = self.list else { return }
        fadeWorkItem?.cancel()
        workItem?.cancel()

        let nextIdx = list.currentStepIndex + 1
        guard nextIdx < list.steps.count else {
            notify(PlaybackState(
                cueListId: list.id, cueListName: list.name,
                currentStepIndex: list.currentStepIndex,
                currentCue: list.steps.last, totalSteps: list.steps.count,
                liveValues: [:], isPlaying: false
            ))
            return
        }

        let nextStep = list.steps[nextIdx]
        fadeSource = [:] // Will receive current live values below

        list.currentStepIndex = nextIdx
        self.list = list

        notify(PlaybackState(
            cueListId: list.id, cueListName: list.name,
            currentStepIndex: nextIdx, currentCue: nextStep,
            totalSteps: list.steps.count,
            liveValues: nextStep.fixtureStates, isPlaying: true
        ))

        let delay = nextStep.delayMs
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // After delay, crossfade
            let source = self.fadeSource
            self.executeCrossfade(from: source, to: nextStep.fixtureStates,
                                  duration: nextStep.fadeInMs, stepIdx: nextIdx)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem!)
    }

    private func executeCrossfade(
        from source: [String: [Int: Int]],
        to target: [String: [Int: Int]],
        duration: TimeInterval, stepIdx: Int
    ) {
        guard let list = self.list else { return }
        let step = list.steps[stepIdx]

        if duration <= 0 {
            notify(PlaybackState(
                cueListId: list.id, cueListName: list.name,
                currentStepIndex: stepIdx, currentCue: step,
                totalSteps: list.steps.count,
                liveValues: target, isPlaying: true
            ))
            afterCue(step: step, stepIdx: stepIdx)
            return
        }

        let startTime = Date()

        func tick() {
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = Float(min(elapsed / duration, 1.0))
            // Smoothstep
            let t = progress * progress * (3 - 2 * progress)
            let live = interpolate(source: source, target: target, t: t)

            notify(PlaybackState(
                cueListId: list.id, cueListName: list.name,
                currentStepIndex: stepIdx, currentCue: step,
                totalSteps: list.steps.count,
                isFading: progress < 1, fadeProgress: progress,
                liveValues: live, isPlaying: true
            ))

            if progress >= 1 {
                afterCue(step: step, stepIdx: stepIdx)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { tick() }
            }
        }

        fadeWorkItem = DispatchWorkItem { tick() }
        DispatchQueue.main.async(execute: fadeWorkItem!)
    }

    private func afterCue(step: CueStep, stepIdx: Int) {
        self.list?.currentStepIndex = stepIdx
        notify(PlaybackState(
            cueListId: list?.id, cueListName: list?.name ?? "",
            currentStepIndex: stepIdx, currentCue: step,
            totalSteps: list?.steps.count ?? 0,
            liveValues: step.fixtureStates, isPlaying: true
        ))

        if step.waitType == .timed, step.waitTimeMs > 0 {
            workItem = DispatchWorkItem { [weak self] in self?.goNext() }
            DispatchQueue.main.asyncAfter(deadline: .now() + step.waitTimeMs, execute: workItem!)
        }
    }

    // ─── Interpolation ──────────────────────────────────────────────────────

    private func interpolate(
        source: [String: [Int: Int]],
        target: [String: [Int: Int]],
        t: Float
    ) -> [String: [Int: Int]] {
        if t <= 0 { return source }
        if t >= 1 { return target }

        var result: [String: [Int: Int]] = [:]
        let allIds = Set(source.keys).union(target.keys)

        for fid in allIds {
            let src = source[fid] ?? [:]
            let tgt = target[fid] ?? [:]
            let allChannels = Set(src.keys).union(tgt.keys)
            var chMap: [Int: Int] = [:]
            for ch in allChannels {
                let s = src[ch] ?? 0
                let tgtVal = tgt[ch] ?? 0
                chMap[ch] = Int(Float(s) + Float(tgtVal - s) * t)
            }
            result[fid] = chMap
        }

        return result
    }

    private func notify(_ state: PlaybackState) {
        fadeSource = state.liveValues
        onStateUpdate?(state)
    }
}
