import AVFoundation
import AppKit

/// Microphone permission handling.
///
/// macOS normally prompts only once; after denial, requestAccess returns false
/// immediately. To request again, reset only this app's decision with
/// `tccutil reset Microphone <bundle id>`, then show the system prompt again.
enum MicPermission {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.fastwhisper.app" }

    static var statusText: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "разрешён"
        case .notDetermined: return "ещё не запрошен"
        case .denied: return "запрещён"
        case .restricted: return "ограничен системой"
        @unknown default: return "неизвестно"
        }
    }

    static var isGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    static func ensure(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            done(true)
        case .notDetermined:
            request(done)
        default:
            askAgain(done)
        }
    }

    private static func request(_ done: @escaping (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async { ok ? done(true) : askAgain(done) }
        }
    }

    private static func askAgain(_ done: @escaping (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Нет доступа к микрофону"
        a.informativeText = "fast-whisper нужен микрофон, чтобы записывать и распознавать речь. "
            + "Звук обрабатывается только на этом Mac и никуда не отправляется."
        a.addButton(withTitle: "Запросить снова")
        a.addButton(withTitle: "Открыть Настройки")
        a.addButton(withTitle: "Отмена")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", "Microphone", bundleID]
            try? p.run(); p.waitUntilExit()
            request(done)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            done(false)
        default:
            done(false)
        }
    }
}
