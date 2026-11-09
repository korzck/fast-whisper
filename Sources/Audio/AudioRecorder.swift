import AVFoundation

/// Microphone recording and pause-based segmentation using energy VAD.
///
/// Audio is converted to mono float32 at 16 kHz and processed in 30 ms frames.
/// Speech threshold is max(noise RMS * 3, 0.008); noise adapts during silence.
/// - Speech starts after three consecutive frames (90 ms) above the threshold.
///   Keep 300 ms of preceding audio to avoid clipping the first consonant.
/// - A pause longer than silenceMs ends the segment (default: 600 ms).
/// - Segments longer than maxSegmentS are split forcibly.
/// - Stopping immediately emits the current segment.
/// Each segment is written to a temporary WAV and passed to onSegment.
final class AudioRecorder {
    var onSegment: ((URL, Double) -> Void)?
    /// Live preview: snapshot the unfinished segment every partialInterval seconds.
    var onPartial: ((URL, Double) -> Void)?
    var onLevel: ((Float) -> Void)?
    var silenceMs: Double = 600
    var maxSegmentS: Double = 15
    var partialInterval: Double = 1.5   // 0 disables live preview.
    private var lastPartialAt = 0
    private var partialCounter = 0

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "fast-whisper.vad")
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?

    private let frameLen = 480                 // 30 ms at 16 kHz.
    private let prerollFrames = 10             // 300 ms.
    private var pendingSamples: [Float] = []
    private var preroll: [[Float]] = []
    private var segment: [Float] = []
    private var inSpeech = false
    private var speechRun = 0
    private var silenceRun = 0
    private var noiseFloor: Float = 0.003
    private var calibration: [Float] = []
    private var counter = 0
    private var levelTick = 0

    private(set) var isRunning = false

    func start() throws {
        queue.sync { resetState() }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "fast-whisper", code: 10, userInfo: [NSLocalizedDescriptionKey: "Нет входного аудиоустройства"])
        }
        converter = AVAudioConverter(from: format, to: target)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buf, _ in
            self?.convertAndProcess(buf)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stop recording and emit the unfinished segment. Call done on the main
    /// thread after the final segment has been delivered to onSegment.
    func stop(done: (() -> Void)? = nil) {
        guard isRunning else { done?(); return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        queue.async { [self] in
            if inSpeech { emit(trimTail: false) }
            resetState()
            DispatchQueue.main.async { done?() }
        }
    }

    private func resetState() {
        pendingSamples.removeAll(); preroll.removeAll(); segment.removeAll()
        inSpeech = false; speechRun = 0; silenceRun = 0; lastPartialAt = 0
        calibration.removeAll(); noiseFloor = 0.003
    }

    private func convertAndProcess(_ buf: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, let ch = out.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
        queue.async { [weak self] in self?.process(samples) }
    }

    private func process(_ samples: [Float]) {
        pendingSamples += samples
        while pendingSamples.count >= frameLen {
            let frame = Array(pendingSamples.prefix(frameLen))
            pendingSamples.removeFirst(frameLen)
            handle(frame)
        }
    }

    private func handle(_ frame: [Float]) {
        var sum: Float = 0
        for s in frame { sum += s * s }
        let rms = (sum / Float(frame.count)).squareRoot()

        levelTick += 1
        if levelTick % 3 == 0 { let l = rms; DispatchQueue.main.async { self.onLevel?(l) } }

        // Calibrate the noise level during the first 300 ms.
        if calibration.count < 10 {
            calibration.append(rms)
            if calibration.count == 10 { noiseFloor = max(0.001, calibration.sorted()[5]) }
        }
        let threshold = max(noiseFloor * 3, 0.008)
        let loud = rms > threshold

        if !inSpeech {
            preroll.append(frame)
            if preroll.count > prerollFrames + 3 { preroll.removeFirst() }
            if loud {
                speechRun += 1
                if speechRun >= 3 {
                    inSpeech = true
                    silenceRun = 0
                    segment = preroll.flatMap { $0 }
                    preroll.removeAll()
                }
            } else {
                speechRun = 0
                noiseFloor = noiseFloor * 0.95 + rms * 0.05
            }
            return
        }

        segment += frame
        if partialInterval > 0, segment.count >= 16_000,
           segment.count - lastPartialAt >= Int(partialInterval * 16_000) {
            lastPartialAt = segment.count
            partialCounter += 1
            let url = Self.tempDir.appendingPathComponent(String(format: "partial-%05d.wav", partialCounter))
            Self.writeWAV(segment, to: url)
            let dur = Double(segment.count) / 16_000
            DispatchQueue.main.async { self.onPartial?(url, dur) }
        }
        silenceRun = loud ? 0 : silenceRun + 1
        let silence = Double(silenceRun * 30)
        let length = Double(segment.count) / 16_000
        if silence >= silenceMs {
            emit(trimTail: true)
        } else if length >= maxSegmentS {
            emit(trimTail: false)
            inSpeech = true          // Speech continues; start the next segment immediately.
        }
    }

    private func emit(trimTail: Bool) {
        var audio = segment
        if trimTail {
            // Keep 200 ms of silence after the last word.
            let drop = max(0, silenceRun - 7) * frameLen
            if drop < audio.count { audio.removeLast(drop) }
        }
        segment.removeAll()
        inSpeech = false; speechRun = 0; silenceRun = 0; lastPartialAt = 0
        let duration = Double(audio.count) / 16_000
        guard duration >= 0.4 else { return }
        counter += 1
        let url = Self.tempDir.appendingPathComponent(String(format: "seg-%05d.wav", counter))
        Self.writeWAV(audio, to: url)
        DispatchQueue.main.async { self.onSegment?(url, duration) }
    }

    /// Self-test: feed recorded 16 kHz samples through the microphone segmentation path.
    /// realtime feeds samples at recording speed for latency measurements.
    func simulate(_ samples: [Float], silenceMs: Double, realtime: Bool = false, done: (() -> Void)? = nil) {
        self.silenceMs = silenceMs
        queue.async { [self] in
            resetState()
            var i = 0
            while i < samples.count {
                process(Array(samples[i..<min(i + 4096, samples.count)]))
                i += 4096
                if realtime { Thread.sleep(forTimeInterval: 4096.0 / 16_000) }
            }
            if inSpeech { emit(trimTail: false) }
            DispatchQueue.main.async { done?() }
        }
    }

    static var tempDir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("fast-whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 16-bit PCM WAV, mono, 16 kHz.
    static func writeWAV(_ samples: [Float], to url: URL) {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1, min(1, s)) * 32_767).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func tag(_ s: String) -> Data { Data(s.utf8) }
        let parts: [Data] = [
            tag("RIFF"), le32(UInt32(36 + pcm.count)), tag("WAVE"),
            tag("fmt "), le32(16), le16(1), le16(1), le32(16_000), le32(32_000), le16(2), le16(16),
            tag("data"), le32(UInt32(pcm.count)), pcm,
        ]
        var file = Data()
        for p in parts { file.append(p) }
        try? file.write(to: url)
    }
}
