import AVFoundation
import AppKit
import SwiftUI

/// `fast-whisper.app/Contents/MacOS/fast-whisper --selftest [file.wav ...]`
///
/// Exercise the pipeline without microphone input or interactive UI. Join recordings
/// with one second of silence, segment with the live VAD, load both models through
/// ModelProcess, and print results and timings.
enum SelfTest {
    static func run(files: [String]) {
        let state = AppState.shared
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--language"), i + 1 < args.count { state.languageOverride = args[i + 1] }
        if let i = args.firstIndex(of: "--engine"), i + 1 < args.count { state.engineOverride = args[i + 1] }
        let recorder = AudioRecorder()
        let start = Date()
        func log(_ s: String) { print(String(format: "[%5.1f s] ", Date().timeIntervalSince(start)) + s); fflush(stdout) }

        var samples: [Float] = []
        let gap = [Float](repeating: 0, count: 16_000)
        for f in files {
            guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: f)),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else {
                log("could not read \(f)"); exit(1)
            }
            samples += gap + Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
        }
        samples += gap
        log("language: \(state.language), recognition: \(state.engineOverride ?? state.settings.asrEngine)")
        log("audio: \(files.count) file(s), \(String(format: "%.1f", Double(samples.count) / 16_000)) s")

        state.startModel(state.asr)
        state.startModel(state.llm)

        var memTimer: Timer?
        memTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            log(String(format: "ASR: %@ %3.0f%% %5.0f MB | LLM: %@ %3.0f%% %5.0f MB",
                       "\(state.asr.status)", state.asr.progress * 100, state.asr.memoryMB,
                       "\(state.llm.status)", state.llm.progress * 100, state.llm.memoryMB))
            if state.asr.status == .failed || state.llm.status == .failed {
                log("ERROR: \(state.asr.lastError ?? state.llm.lastError ?? "")"); exit(1)
            }
            guard state.asr.status == .ready, state.llm.status == .ready else { return }
            memTimer?.invalidate()
            log("both models ready; feeding audio")
            let realtime = CommandLine.arguments.contains("--realtime")
            var partialEmitted: [Date] = []
            var segmentEmitted: [Int: Date] = [:]
            var rawShown = Set<Int>()
            var lastPartial = ""
            recorder.partialInterval = state.settings.livePreview ? state.settings.partialInterval : 0
            recorder.onPartial = { url, dur in
                partialEmitted.append(Date())
                state.injectPartial(url, dur)
            }
            recorder.onSegment = { url, dur in
                log(String(format: "segment %.1f s ended (pause) -> models", dur))
                let before = Set(state.segments.map(\.id))
                state.injectSegment(url, dur)
                if let s = state.segments.first(where: { !before.contains($0.id) }) { segmentEmitted[s.id] = Date() }
            }
            // Track when transcript text becomes visible.
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                if state.partialText != lastPartial, !state.partialText.isEmpty {
                    lastPartial = state.partialText
                    let lag = partialEmitted.last.map { Date().timeIntervalSince($0) } ?? -1
                    log(String(format: "preview (%.2f s after snapshot): %@", lag, state.partialText))
                }
                for s in state.segments where s.asrMs != nil && !rawShown.contains(s.id) {
                    rawShown.insert(s.id)
                    if let t = segmentEmitted[s.id] {
                        log(String(format: "segment %d recognized %.2f s after pause", s.id, Date().timeIntervalSince(t)))
                    }
                }
            }
            var fed = false
            recorder.simulate(samples, silenceMs: state.settings.silenceMs, realtime: realtime) { fed = true }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
                guard fed, !state.segments.isEmpty, state.segments.allSatisfy({ $0.state == .done }) else { return }
                t.invalidate()
                for s in state.segments {
                    log("segment \(s.id): \(state.loadedASREngine == "gigaam" ? "GigaAM" : "Whisper") \(s.asrMs ?? -1) ms, Gemma \(s.llmMs ?? -1) ms\n    raw: \(s.raw)\n    final:  \(s.final)")
                }
                log("FINAL TRANSCRIPT:\n\(state.fullText)")
                log("text to paste (session \(state.session)):\n\(state.sessionText(state.session))")
                if let i = CommandLine.arguments.firstIndex(of: "--render-overlay"), i + 1 < CommandLine.arguments.count {
                    // Capture the overlay as it appears during recording.
                    state.overlayPhase = .recording
                    state.partialText = "а это то, что говорится прямо сейчас"
                    let v = NSHostingView(rootView: OverlayView(state: state))
                    v.frame = NSRect(origin: .zero, size: OverlayController.size)
                    v.appearance = NSAppearance(named: .darkAqua)
                    v.layoutSubtreeIfNeeded()
                    if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                        log("overlay rendered to \(CommandLine.arguments[i + 1])")
                    }
                }
                state.asr.stop(); state.llm.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
            }
        }
    }
}
