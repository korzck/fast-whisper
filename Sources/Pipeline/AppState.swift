import AppKit
import Combine

/// Application state and pipeline: segment -> Whisper -> Gemma -> transcript.
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings = Settings()
    let asr = ModelProcess(id: "asr",
                           title: "Распознавание речи",
                           subtitle: "Whisper large-v3-turbo · whisper.cpp q5_0 · энкодер на Neural Engine",
                           expectedMB: 720)
    let llm = ModelProcess(id: "llm",
                           title: "Исправление текста",
                           subtitle: "Gemma 3 4B · MLX 4-bit · GPU",
                           expectedMB: 2900)

    @Published var isRecording = false
    @Published var overlayPhase: OverlayPhase = .hidden
    @Published var axTrusted = Paster.isTrusted
    @Published var segments: [Segment] = [] { didSet { sessionVersion += 1 } }
    /// Transcript revision counter used to scroll the overlay to the bottom.
    @Published var sessionVersion = 0
    /// Unfinished segment text: live preview without LLM correction.
    @Published var partialText = ""
    private var partialInFlight = false
    private var openSegmentToken = 0
    @Published var level: Float = 0
    @Published var notice: String?
    @Published var micStatus = MicPermission.statusText

    private let recorder = AudioRecorder()
    private var nextSegmentID = 1
    private(set) var session = 0
    private var bag = Set<AnyCancellable>()

    init() {
        asr.subtitle = settings.asrEngineInfo.subtitle
        // Forward child-object changes so SwiftUI refreshes the window.
        for o in [asr.objectWillChange, llm.objectWillChange, settings.objectWillChange] {
            o.receive(on: DispatchQueue.main).sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        }
        recorder.onSegment = { [weak self] url, dur in self?.handleSegment(url, dur) }
        recorder.onPartial = { [weak self] url, dur in self?.handlePartial(url, dur) }
        recorder.onLevel = { [weak self] l in self?.level = l }
        // Poll Accessibility trust: macOS does not publish change notifications.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            let t = Paster.isTrusted
            if self?.axTrusted != t { self?.axTrusted = t }
        }
    }

    var sessionIsEmpty: Bool {
        partialText.isEmpty && !segments.contains { $0.session == session }
    }

    /// Text for one recording session, ready to paste into the active field.
    func sessionText(_ s: Int) -> String {
        var parts: [String] = []
        for (i, seg) in segments.enumerated() where seg.session == s && !seg.text.isEmpty {
            parts.append(displayText(at: i))
        }
        return parts.joined(separator: " ")
    }

    // MARK: Models

    func startModel(_ m: ModelProcess) {
        if m === asr {
            // The self-test selects an engine without changing user preferences.
            let engine = engineOverride ?? settings.asrEngine
            asr.subtitle = Settings.asrEngines.first { $0.code == engine }?.subtitle ?? asr.subtitle
            loadedASREngine = engine
            m.start(glossary: settings.glossary, language: language, extra: ["engine": engine])
        } else {
            m.start(glossary: settings.glossary, language: language)
        }
    }

    /// Self-test recognition engine override (--engine gigaam).
    var engineOverride: String?
    /// Currently loaded recognition engine; the picker changes only after unloading.
    @Published var loadedASREngine = ""

    /// GigaAM supports Russian only; warn when English is selected.
    var asrLanguageWarning: String? {
        settings.asrEngine == "gigaam" && language != "ru"
            ? "GigaAM распознаёт только русский, а в настройках выбран English" : nil
    }

    /// Recognition language from settings, with a nonpersistent self-test override.
    var languageOverride: String?
    var language: String { languageOverride ?? settings.language }
    func stopModel(_ m: ModelProcess) { m.stop() }

    // MARK: Recording

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    func startRecording() {
        guard !isRecording else { return }
        guard overlayPhase != .finishing else { NSSound.beep(); return }   // Still pasting the previous recording.
        guard asr.status == .ready else {
            notice = asr.isRunning
                ? "Модель распознавания ещё загружается — подождите несколько секунд."
                : "Сначала запустите модель распознавания речи."
            NSSound.beep()
            AppDelegate.shared?.showMainWindow()
            return
        }
        MicPermission.ensure { [weak self] ok in
            guard let self else { return }
            self.micStatus = MicPermission.statusText
            guard ok else { self.notice = "Нет доступа к микрофону."; return }
            self.recorder.silenceMs = self.settings.silenceMs
            self.recorder.partialInterval = self.settings.livePreview ? self.settings.partialInterval : 0
            self.partialText = ""
            do {
                try self.recorder.start()
                self.session += 1
                self.isRecording = true
                self.notice = nil
                NSSound(named: "Tink")?.play()
                if self.settings.showOverlay {
                    self.overlayPhase = .recording
                    OverlayController.shared.show()
                }
            } catch {
                self.notice = "Не удалось начать запись: \(error.localizedDescription)"
            }
            AppDelegate.shared?.refreshStatusItem()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        let s = session
        isRecording = false
        level = 0
        NSSound(named: "Pop")?.play()
        AppDelegate.shared?.refreshStatusItem()
        if settings.showOverlay { overlayPhase = .finishing }
        // recorder.stop emits the final segment. Wait for all session segments
        // to finish recognition and correction before pasting the text.
        recorder.stop { [weak self] in self?.finishSession(s, startedAt: Date()) }
    }

    private func finishSession(_ s: Int, startedAt: Date) {
        let pending = segments.contains { $0.session == s && $0.state != .done }
        if pending && Date().timeIntervalSince(startedAt) < 12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.finishSession(s, startedAt: startedAt) }
            return
        }
        partialText = ""
        let text = sessionText(s)
        let phase: OverlayPhase
        if text.isEmpty {
            phase = .empty
        } else if !settings.autoPaste {
            Paster.copy(text); phase = .clipboard
        } else if Paster.paste(text, restoreClipboard: settings.restoreClipboard) {
            phase = .inserted
        } else {
            phase = .copied   // No access; the text is already on the clipboard.
            Paster.requestTrust()
        }
        guard settings.showOverlay else { return }
        overlayPhase = phase
        OverlayController.shared.hide(after: phase == .copied ? 4 : 1.2)
    }

    // MARK: Pipeline

    /// Self-test entry point for segments read from a file instead of the microphone.
    func injectSegment(_ url: URL, _ duration: Double) {
        if session == 0 { session = 1 }
        handleSegment(url, duration)
    }

    func injectPartial(_ url: URL, _ duration: Double) { handlePartial(url, duration) }

    /// Unfinished snapshot -> Whisper -> gray preview at the end of the transcript.
    /// Skip a snapshot if Whisper is still processing the previous one; completed
    /// segments take priority over live preview.
    private func handlePartial(_ url: URL, _ duration: Double) {
        guard !partialInFlight, asr.status == .ready else { try? FileManager.default.removeItem(at: url); return }
        partialInFlight = true
        let token = openSegmentToken
        asr.request(["cmd": "transcribe", "path": url.path, "language": language]) { [weak self] result in
            try? FileManager.default.removeItem(at: url)
            guard let self else { return }
            self.partialInFlight = false
            // The segment has ended; its final recognition result will arrive separately.
            guard token == self.openSegmentToken, case .success(let r) = result else { return }
            self.partialText = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func handleSegment(_ url: URL, _ duration: Double) {
        let id = nextSegmentID; nextSegmentID += 1
        openSegmentToken += 1
        var seg = Segment(id: id, session: session, duration: duration)
        seg.raw = partialText          // Show preview while full recognition is pending.
        partialText = ""
        segments.append(seg)
        asr.request(["cmd": "transcribe", "path": url.path, "language": language]) { [weak self] result in
            try? FileManager.default.removeItem(at: url)
            guard let self, let i = self.index(id) else { return }
            switch result {
            case .failure(let e):
                self.notice = "Ошибка распознавания: \(e.localizedDescription)"
                self.segments.remove(at: i)
            case .success(let r):
                let raw = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty || self.isEcho(raw, before: i) { self.segments.remove(at: i); return }
                self.segments[i].raw = raw
                self.segments[i].asrMs = r.ms
                self.correct(id: id, raw: raw)
            }
        }
    }

    private func correct(id: Int, raw: String) {
        guard let i = index(id) else { return }
        guard settings.useLLM, llm.status == .ready else {
            segments[i].final = settings.applyReplacements(raw)
            segments[i].state = .done
            return
        }
        segments[i].state = .correcting
        let context = String(segments[..<i].map(\.text).joined(separator: " ").suffix(200))
        llm.request(["cmd": "correct", "text": raw, "context": context, "language": language]) { [weak self] result in
            guard let self, let j = self.index(id) else { return }
            switch result {
            case .success(let r):
                self.segments[j].final = self.settings.applyReplacements(r.text)
                self.segments[j].llmMs = r.ms
            case .failure:
                self.segments[j].final = self.settings.applyReplacements(raw)
            }
            self.segments[j].state = .done
        }
    }

    private func index(_ id: Int) -> Int? { segments.firstIndex { $0.id == id } }

    /// Detect a short fragment repeating the previous segment's suffix. A pause
    /// inside a term such as "whisper... cpp" can split its ending even though
    /// Whisper already completed the term using the glossary.
    private func isEcho(_ text: String, before i: Int) -> Bool {
        guard i > 0, segments[i].duration < 1.2 else { return false }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let cur = norm(text), prev = norm(segments[i - 1].raw)
        return !cur.isEmpty && cur.count <= 12 && prev.hasSuffix(cur)
    }

    // MARK: Text

    /// Adjust segment boundaries: if the next segment in the same recording starts
    /// with a lowercase letter, replace this segment's trailing period with a comma
    /// to join a sentence interrupted by a pause.
    func displayText(at i: Int) -> String {
        var t = segments[i].text
        guard i + 1 < segments.count, segments[i + 1].session == segments[i].session,
              let first = segments[i + 1].text.first, let lastChar = t.last else { return t }
        if first.isLowercase, lastChar == "." {
            t.removeLast(); t += ","
        } else if first.isUppercase, !".!?…:;,".contains(lastChar) {
            // The next segment starts a new sentence, but this one has no ending punctuation.
            t += "."
        }
        return t
    }

    /// Join segments with spaces within a recording and separate recordings with newlines.
    var fullText: String {
        var out = "", last = -1
        for (i, s) in segments.enumerated() where !s.text.isEmpty {
            if last != -1 { out += s.session == last ? " " : "\n\n" }
            out += displayText(at: i)
            last = s.session
        }
        return out
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
    }

    func clear() { segments.removeAll(); partialText = "" }
}
