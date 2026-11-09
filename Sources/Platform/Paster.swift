import AppKit
import ApplicationServices

/// Paste at the current cursor position in any application.
///
/// Place text on the clipboard and synthesize Command-V. Sending key events to
/// other applications requires macOS Accessibility permission.
/// Restore the previous clipboard contents after half a second.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Show the system prompt requesting permission to control the computer.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Offer to request access again when trust is missing. Rebuilding changes the
    /// signature and can invalidate an existing Accessibility entry, so reset
    /// the old entry before asking again.
    static func askAgain() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Нет доступа к «Универсальному доступу»"
        a.informativeText = "Чтобы вставлять текст туда, где стоит курсор, fast-whisper нужно разрешение "
            + "«Универсальный доступ» (Системные настройки → Конфиденциальность и безопасность). "
            + "Пока его нет, текст копируется в буфер обмена — вставьте его через ⌘V."
        a.addButton(withTitle: "Запросить снова")
        a.addButton(withTitle: "Открыть Настройки")
        a.addButton(withTitle: "Отмена")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", "Accessibility", MicPermission.bundleID]
            try? p.run(); p.waitUntilExit()
            requestTrust()
        case .alertSecondButtonReturn:
            openSettings()
        default: break
        }
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Paste into the active field. Return false without access; text remains on the clipboard.
    static func paste(_ text: String, restoreClipboard: Bool) -> Bool {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        copy(text)
        guard isTrusted else { return false }

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // Physical V key; works with the Russian keyboard layout too.
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        if restoreClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pb.clearContents()
                let items = saved.map { pairs -> NSPasteboardItem in
                    let it = NSPasteboardItem()
                    for (t, d) in pairs { it.setData(d, forType: t) }
                    return it
                }
                if !items.isEmpty { pb.writeObjects(items) }
            }
        }
        return true
    }
}
