import Foundation
import Carbon
import AppKit

/// Application preferences persisted in UserDefaults.
final class Settings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var hotKeyCode: UInt32 { didSet { d.set(hotKeyCode, forKey: "hotKeyCode") } }
    @Published var hotKeyMods: UInt32 { didSet { d.set(hotKeyMods, forKey: "hotKeyMods") } }
    @Published var hotKeyDisplay: String { didSet { d.set(hotKeyDisplay, forKey: "hotKeyDisplay") } }
    /// Recognition and correction language: "en" (default) or "ru".
    @Published var language: String { didSet { d.set(language, forKey: "language") } }

    static let languages: [(code: String, name: String)] = [("en", "English"), ("ru", "Русский")]
    var languageName: String { Self.languages.first { $0.code == language }?.name ?? language }
    /// Silence duration in milliseconds before a completed segment is sent to the model.
    @Published var silenceMs: Double { didSet { d.set(silenceMs, forKey: "silenceMs") } }
    @Published var useLLM: Bool { didSet { d.set(useLLM, forKey: "useLLM") } }
    /// Show live text while speaking, without waiting for a pause.
    @Published var livePreview: Bool { didSet { d.set(livePreview, forKey: "livePreview") } }
    /// Live preview refresh interval in seconds.
    @Published var partialInterval: Double { didSet { d.set(partialInterval, forKey: "partialInterval") } }
    @Published var autoLoad: Bool { didSet { d.set(autoLoad, forKey: "autoLoad") } }
    /// Show the floating transcript overlay at the bottom right.
    @Published var showOverlay: Bool { didSet { d.set(showOverlay, forKey: "showOverlay") } }
    /// Paste at the current cursor position after recording stops.
    @Published var autoPaste: Bool { didSet { d.set(autoPaste, forKey: "autoPaste") } }
    /// Restore previous clipboard contents after pasting.
    @Published var restoreClipboard: Bool { didSet { d.set(restoreClipboard, forKey: "restoreClipboard") } }
    /// Glossary for Whisper and the LLM; applied when loading a model.
    @Published var glossary: String { didSet { d.set(glossary, forKey: "glossary") } }
    /// Recognition engine: "whisper" (large-v3-turbo) or "gigaam" (Russian-only GigaAM-v3).
    @Published var asrEngine: String { didSet { d.set(asrEngine, forKey: "asrEngine") } }
    static let asrEngines: [(code: String, name: String, subtitle: String, hint: String)] = [
        ("whisper", "Whisper large-v3-turbo",
         "Whisper large-v3-turbo · whisper.cpp q5_0 · энкодер на Neural Engine",
         "Английский и русский · ~0,9 с на фразу · ~0,7 ГБ"),
        ("gigaam", "GigaAM-v3 (русский)",
         "GigaAM-v3 · Сбер · ONNX int8 · CPU",
         "Только русский · ~0,1–0,3 с на фразу · ~0,5 ГБ · хуже пишет английские термины"),
    ]
    var asrEngineInfo: (code: String, name: String, subtitle: String, hint: String) {
        Self.asrEngines.first { $0.code == asrEngine } ?? Self.asrEngines[0]
    }
    /// Post-LLM replacements, one "source => replacement" pair per line.
    @Published var replacements: String { didSet { d.set(replacements, forKey: "replacements") } }

    init() {
        d.register(defaults: [
            "hotKeyCode": 49,                                     // Space
            "hotKeyMods": controlKey | optionKey,                 // ⌃⌥
            "hotKeyDisplay": "⌃⌥Space",
            "language": "en",
            "asrEngine": "whisper",
            "silenceMs": 600.0,
            "useLLM": true,
            "livePreview": true,
            "partialInterval": 1.5,
            "autoLoad": false,
            "showOverlay": true,
            "autoPaste": true,
            "restoreClipboard": true,
            "glossary": "Claude Code, Claude, Anthropic, npm, git, GitHub, CI, PostgreSQL, Kubernetes, "
                + "Nginx, Docker, Hugging Face, MLX, whisper.cpp, Python, Swift, Qwen, Gemma",
            "replacements": "Cloud Code => Claude Code\nклоуд код => Claude Code\nклод код => Claude Code",
        ])
        hotKeyCode = UInt32(d.integer(forKey: "hotKeyCode"))
        hotKeyMods = UInt32(d.integer(forKey: "hotKeyMods"))
        hotKeyDisplay = d.string(forKey: "hotKeyDisplay") ?? "⌃⌥Space"
        language = d.string(forKey: "language") ?? "en"
        asrEngine = d.string(forKey: "asrEngine") ?? "whisper"
        silenceMs = d.double(forKey: "silenceMs")
        useLLM = d.bool(forKey: "useLLM")
        livePreview = d.bool(forKey: "livePreview")
        partialInterval = d.double(forKey: "partialInterval")
        autoLoad = d.bool(forKey: "autoLoad")
        showOverlay = d.bool(forKey: "showOverlay")
        autoPaste = d.bool(forKey: "autoPaste")
        restoreClipboard = d.bool(forKey: "restoreClipboard")
        glossary = d.string(forKey: "glossary") ?? ""
        replacements = d.string(forKey: "replacements") ?? ""
    }

    /// Apply case-insensitive dictionary replacements.
    func applyReplacements(_ text: String) -> String {
        var out = text
        for line in replacements.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let from = parts[0].trimmingCharacters(in: .whitespaces)
            let to = parts[1].trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty else { continue }
            out = out.replacingOccurrences(of: from, with: to, options: [.caseInsensitive])
        }
        return out
    }
}
