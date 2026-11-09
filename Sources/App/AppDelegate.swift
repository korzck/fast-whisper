import AppKit
import SwiftUI

/// Menu-bar application with no Dock icon. Opens the main window on launch
/// to load models and display the transcript.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private let state = AppState.shared
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let recordItem = NSMenuItem(title: "", action: #selector(toggleRecording), keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest") {
            NSApp.setActivationPolicy(.prohibited)
            SelfTest.run(files: args[(i + 1)...].filter { $0.hasSuffix(".wav") })
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Открыть fast-whisper", action: #selector(openMain), keyEquivalent: "").target = self
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из fast-whisper", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu

        HotKey.shared.onPress = { [weak self] in self?.state.toggleRecording() }
        HotKey.shared.register(keyCode: state.settings.hotKeyCode, modifiers: state.settings.hotKeyMods)

        refreshStatusItem()
        showMainWindow()

        // Request microphone access on launch, then Accessibility access
        // for pasting into the active field.
        MicPermission.ensure { [weak self] _ in
            guard let self else { return }
            self.state.micStatus = MicPermission.statusText
            if self.state.settings.autoPaste && !Paster.isTrusted { Paster.requestTrust() }
        }

        if state.settings.autoLoad {
            state.startModel(state.asr)
            state.startModel(state.llm)
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        state.asr.stop(); state.llm.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(); return true
    }

    // MARK: Menu bar

    func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let rec = state.isRecording
        button.image = NSImage(systemSymbolName: rec ? "record.circle.fill" : "waveform",
                               accessibilityDescription: "fast-whisper")
        button.imagePosition = .imageLeading
        button.contentTintColor = rec ? .systemRed : nil
        button.title = " fast-whisper"
        recordItem.title = (rec ? "Остановить запись" : "Начать запись") + "   \(state.settings.hotKeyDisplay)"
    }

    func menuWillOpen(_ menu: NSMenu) { refreshStatusItem() }

    // MARK: Windows

    func showMainWindow() {
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "fast-whisper"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(state: state))
            w.center()
            w.setFrameAutosaveName("fast-whisper.main")
            mainWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 820),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Настройки fast-whisper"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: state.settings, state: state))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openMain() { showMainWindow() }
    @objc private func openSettings() { showSettings() }
    @objc private func toggleRecording() { state.toggleRecording() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Apps without a Dock icon have no visible main menu. Add the standard Edit
    /// menu so Command-C, Command-V and Command-A work in text fields.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать все", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
