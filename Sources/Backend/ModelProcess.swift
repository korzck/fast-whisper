import Foundation
import Darwin

/// Process memory in MB: phys_footprint, matching Activity Monitor's Memory column.
func footprintMB(pid: pid_t) -> Double? {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    return rc == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : nil
}

/// One model hosted in a separate Python process (backend.py).
/// Exchanges JSON lines over stdin/stdout; polls memory every 250 ms
/// to visualize model loading into RAM.
final class ModelProcess: ObservableObject, Identifiable {
    enum Status: Equatable { case stopped, loading, ready, failed }

    let id: String          // "asr" | "llm"
    let title: String
    @Published var subtitle: String
    let expectedMB: Double  // Expected loaded model memory from benchmarks.

    @Published var status: Status = .stopped
    @Published var stage = "Не запущена"
    @Published var progress: Double = 0
    @Published var memoryMB: Double = 0
    @Published var peakMB: Double = 0
    @Published var elapsed: Double = 0
    @Published var loadSeconds: Double?
    @Published var lastError: String?

    private var process: Process?
    private var stdin: FileHandle?
    private var lineBuffer = Data()
    private var stageProgress: Double = 0
    private var pending: [Int: (Result<(text: String, ms: Int), Error>) -> Void] = [:]
    private var nextID = 1
    private var timer: Timer?
    private var startedAt = Date()

    init(id: String, title: String, subtitle: String, expectedMB: Double) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.expectedMB = expectedMB
    }

    var isRunning: Bool { status == .loading || status == .ready }

    static var projectRoot: URL {
        if let p = Bundle.main.object(forInfoDictionaryKey: "FWProjectRoot") as? String {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static var logDir: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/fast-whisper")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Start / stop

    func start(glossary: String, language: String, extra: [String: Any] = [:]) {
        guard !isRunning else { return }
        let root = Self.projectRoot
        let python = root.appendingPathComponent(".venv/bin/python")
        let script = root.appendingPathComponent("backend.py")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            fail("Не найден Python окружения: \(python.path)"); return
        }

        let p = Process()
        p.executableURL = python
        p.arguments = ["-u", script.path, id]
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONPATH"] = root.path
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        let logURL = Self.logDir.appendingPathComponent("\(id).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        p.standardError = try? FileHandle(forWritingTo: logURL)

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.terminated(code: proc.terminationStatus) }
        }

        status = .loading
        stage = "Запуск процесса Python"
        progress = 0; stageProgress = 0; memoryMB = 0; peakMB = 0; elapsed = 0
        loadSeconds = nil; lastError = nil
        startedAt = Date()
        do { try p.run() } catch { fail("Не удалось запустить: \(error.localizedDescription)"); return }
        process = p
        stdin = inPipe.fileHandleForWriting
        startTimer()
        var load: [String: Any] = ["id": 0, "cmd": "load", "glossary": glossary, "language": language]
        load.merge(extra) { _, new in new }
        send(load)
    }

    func stop() {
        guard let p = process else { return }
        send(["cmd": "quit"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { if p.isRunning { p.terminate() } }
    }

    // MARK: Requests

    func request(_ payload: [String: Any], completion: @escaping (Result<(text: String, ms: Int), Error>) -> Void) {
        guard status == .ready else {
            completion(.failure(NSError(domain: "fast-whisper", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Модель не загружена"])))
            return
        }
        let rid = nextID; nextID += 1
        pending[rid] = completion
        var msg = payload; msg["id"] = rid
        send(msg)
    }

    private func send(_ msg: [String: Any]) {
        guard let stdin, let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        try? stdin.write(contentsOf: data + Data([0x0A]))
    }

    // MARK: Server responses

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<nl]
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(obj)
        }
    }

    private func handle(_ m: [String: Any]) {
        if let rid = m["id"] as? Int, let cb = pending.removeValue(forKey: rid) {
            if m["ok"] as? Bool == true {
                cb(.success((m["text"] as? String ?? "", m["ms"] as? Int ?? 0)))
            } else {
                cb(.failure(NSError(domain: "fast-whisper", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: m["message"] as? String ?? "ошибка"])))
            }
            return
        }
        switch m["event"] as? String {
        case "stage":
            stage = m["stage"] as? String ?? stage
            stageProgress = m["progress"] as? Double ?? stageProgress
            updateProgress()
        case "ready":
            status = .ready
            loadSeconds = m["load_s"] as? Double
            stage = "Готова, держится в оперативной памяти"
            progress = 1
        case "error":
            if status == .loading { fail(m["message"] as? String ?? "ошибка загрузки") }
            else { lastError = m["message"] as? String }
        default: break
        }
    }

    private func terminated(code: Int32) {
        timer?.invalidate(); timer = nil
        process = nil; stdin = nil
        for (_, cb) in pending {
            cb(.failure(NSError(domain: "fast-whisper", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Процесс модели завершился"])))
        }
        pending.removeAll()
        if status == .failed { return }
        if status == .loading || code != 0 && code != 15 {
            fail("Процесс завершился (код \(code)). Лог: ~/Library/Logs/fast-whisper/\(id).log")
        } else {
            status = .stopped; stage = "Выгружена"; progress = 0; memoryMB = 0
        }
    }

    private func fail(_ message: String) {
        status = .failed
        stage = "Ошибка"
        lastError = message
        progress = 0
        if let p = process, p.isRunning { p.terminate() }
    }

    // MARK: Memory polling

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let p = self.process else { return }
            if let mb = footprintMB(pid: p.processIdentifier) {
                self.memoryMB = mb
                self.peakMB = max(self.peakMB, mb)
            }
            if self.status == .loading {
                self.elapsed = Date().timeIntervalSince(self.startedAt)
                self.updateProgress()
            }
        }
    }

    /// Loading progress is the maximum of the reported stage and the fraction
    /// of expected memory already allocated as weights load into RAM.
    private func updateProgress() {
        guard status == .loading else { return }
        let byMemory = min(0.9, memoryMB / expectedMB)
        progress = max(progress, stageProgress, byMemory)
    }
}
