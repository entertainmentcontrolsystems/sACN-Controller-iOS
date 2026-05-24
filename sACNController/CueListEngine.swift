import Foundation

/// Cue List crossfade engine — iOS port of the Android CueListEngine.
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

    func start(list: CueList, onUpdate: @escaping (PlaybackState) -> Void) {
        stop()
        self.list = list
        self.onStateUpdate = onUpdate
        fadeSource = [:]
        if !list.steps.isEmpty { goNext() }
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
            self.list?.currentStepIndex = prevIdx
            notify(PlaybackState(cueListId: list.id, cueListName: list.name,
                currentStepIndex: prevIdx, currentCue: prevCue,
                isPlaying: true, totalSteps: list.steps.count,
                liveValues: prevCue?.fixtureStates ?? [:]))
        } else {
            let currentVals = fadeSource
            fadeSource = currentVals.isEmpty ? (prevCue?.fixtureStates ?? [:]) : currentVals
            notify(PlaybackState(cueListId: list.id, cueListName: list.name,
                currentStepIndex: prevIdx, currentCue: prevCue,
                isPlaying: true, totalSteps: list.steps.count,
                liveValues: fadeSource))
            executeCrossfade(from: fadeSource, to: prevCue!.fixtureStates,
                             duration: fadeTime, stepIdx: prevIdx)
        }
    }

    private func goNext() {
        guard var list = self.list else { return }
        fadeWorkItem?.cancel(); workItem?.cancel()
        let nextIdx = list.currentStepIndex + 1
        guard nextIdx < list.steps.count else {
            notify(PlaybackState(cueListId: list.id, cueListName: list.name,
                currentStepIndex: list.currentStepIndex,
                currentCue: list.steps.last, isPlaying: false,
                totalSteps: list.steps.count, liveValues: [:]))
            return
        }

        let nextStep = list.steps[nextIdx]
        fadeSource = [:]
        list.currentStepIndex = nextIdx
        self.list = list

        notify(PlaybackState(cueListId: list.id, cueListName: list.name,
            currentStepIndex: nextIdx, currentCue: nextStep,
            isPlaying: true, totalSteps: list.steps.count,
            liveValues: nextStep.fixtureStates))

        let delay = nextStep.delayMs
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let source = self.fadeSource
            self.executeCrossfade(from: source, to: nextStep.fixtureStates,
                                  duration: nextStep.fadeInMs, stepIdx: nextIdx)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem!)
    }

    private func executeCrossfade(from source: [String: [Int: Int]],
                                  to target: [String: [Int: Int]],
                                  duration: TimeInterval, stepIdx: Int) {
        guard let list = self.list else { return }
        let step = list.steps[stepIdx]

        if duration <= 0 {
            notify(PlaybackState(cueListId: list.id, cueListName: list.name,
                currentStepIndex: stepIdx, currentCue: step,
                isPlaying: true, totalSteps: list.steps.count,
                liveValues: target))
            afterCue(step: step, stepIdx: stepIdx)
            return
        }

        let startTime = Date()
        func tick() {
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = Float(min(elapsed / duration, 1.0))
            let t = progress * progress * (3 - 2 * progress)
            let live = interpolate(source: source, target: target, t: t)
            notify(PlaybackState(cueListId: list.id, cueListName: list.name,
                currentStepIndex: stepIdx, currentCue: step,
                isPlaying: true, isFading: progress < 1,
                fadeProgress: progress, totalSteps: list.steps.count,
                liveValues: live))
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
        notify(PlaybackState(cueListId: list?.id, cueListName: list?.name ?? "",
            currentStepIndex: stepIdx, currentCue: step,
            isPlaying: true, totalSteps: list?.steps.count ?? 0,
            liveValues: step.fixtureStates))
        if step.waitType == .timed, step.waitTimeMs > 0 {
            workItem = DispatchWorkItem { [weak self] in self?.goNext() }
            DispatchQueue.main.asyncAfter(deadline: .now() + step.waitTimeMs, execute: workItem!)
        }
    }

    private func interpolate(source: [String: [Int: Int]], target: [String: [Int: Int]], t: Float) -> [String: [Int: Int]] {
        if t <= 0 { return source }; if t >= 1 { return target }
        var result: [String: [Int: Int]] = [:]
        for fid in Set(source.keys).union(target.keys) {
            let src = source[fid] ?? [:]; let tgt = target[fid] ?? [:]
            var chMap: [Int: Int] = [:]
            for ch in Set(src.keys).union(tgt.keys) {
                let s = src[ch] ?? 0; let tgtVal = tgt[ch] ?? 0
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
