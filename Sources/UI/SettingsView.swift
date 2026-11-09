// MARK: - Settings

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AppState
    @State private var capturing = false
    @State private var monitor: Any?
    @State private var hint = ""

    var body: some View {
        Form {
            Section("Горячая клавиша") {
                HStack {
                    Text(capturing ? "Нажмите сочетание…" : settings.hotKeyDisplay)
                        .font(.system(.title3, design: .rounded)).monospaced()
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    Button(capturing ? "Отмена" : "Изменить") { capturing ? endCapture() : beginCapture() }
                    Spacer()
                }
                Text(hint.isEmpty ? "Первое нажатие начинает запись, второе — останавливает. Нужен хотя бы один модификатор (⌃ ⌥ ⇧ ⌘) или F-клавиша."
                                  : hint)
                    .font(.caption).foregroundStyle(hint.isEmpty ? Color.secondary : Color.red)
            }
            Section("Язык распознавания") {
                Picker("Язык", selection: $settings.language) {
                    ForEach(Settings.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                .pickerStyle(.segmented)
                Text("Язык речи для Whisper и язык инструкции для Gemma. Переключается сразу, без перезагрузки моделей.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Запись") {
                HStack {
                    Text("Пауза, после которой фраза уходит в модель")
                    Slider(value: $settings.silenceMs, in: 300...1500, step: 50)
                    Text("\(Int(settings.silenceMs)) мс").monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                Toggle("Показывать текст во время речи, не дожидаясь паузы", isOn: $settings.livePreview)
                HStack {
                    Text("Обновлять каждые")
                    Slider(value: $settings.partialInterval, in: 1.0...3.0, step: 0.25)
                    Text(String(format: "%.2g с", settings.partialInterval)).monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                .disabled(!settings.livePreview)
                HStack {
                    Text("Микрофон: \(state.micStatus)")
                    Spacer()
                    Button("Проверить / запросить доступ") {
                        MicPermission.ensure { _ in state.micStatus = MicPermission.statusText }
                    }
                }
            }
            Section("Окошко и вставка текста") {
                Toggle("Показывать окошко с текстом справа снизу во время записи", isOn: $settings.showOverlay)
                Toggle("После остановки вставлять текст туда, где стоит курсор", isOn: $settings.autoPaste)
                Toggle("Возвращать прежнее содержимое буфера обмена после вставки", isOn: $settings.restoreClipboard)
                    .disabled(!settings.autoPaste)
                HStack {
                    Text("Универсальный доступ: \(state.axTrusted ? "разрешён" : "нет")")
                    Spacer()
                    Button(state.axTrusted ? "Открыть Настройки" : "Запросить доступ") {
                        state.axTrusted ? Paster.openSettings() : Paster.askAgain()
                    }
                }
                Text("Вставка работает так: текст кладётся в буфер обмена и программно нажимается ⌘V. "
                     + "Для этого macOS требует разрешение «Универсальный доступ». После пересборки "
                     + "приложения его нужно выдать заново («Запросить доступ»).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Модели") {
                Toggle("Исправлять текст через LLM (Gemma 3 4B)", isOn: $settings.useLLM)
                Toggle("Загружать обе модели при запуске приложения", isOn: $settings.autoLoad)
            }
            Section("Словарь терминов") {
                TextEditor(text: $settings.glossary).frame(height: 60).font(.callout)
                Text("Подсказка Whisper и LLM, как писать термины. Применяется при следующем запуске модели.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Замены после исправления") {
                TextEditor(text: $settings.replacements).frame(height: 80).font(.system(.callout, design: .monospaced))
                Text("По одной на строку: «что => на что». Без учёта регистра. Применяются сразу.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 820)
        .onDisappear { endCapture() }
    }

    private func beginCapture() {
        capturing = true; hint = ""
        HotKey.shared.unregister()   // Allow capturing the current shortcut too.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = HotKey.carbonModifiers(e.modifierFlags)
            if e.keyCode == 53 && mods == 0 { endCapture(); return nil }   // Esc cancels capture.
            guard mods != 0 || HotKey.isFunctionKey(e.keyCode) else {
                hint = "Добавьте модификатор: ⌃, ⌥, ⇧ или ⌘."
                return nil
            }
            settings.hotKeyCode = UInt32(e.keyCode)
            settings.hotKeyMods = mods
            settings.hotKeyDisplay = HotKey.display(e)
            endCapture()
            return nil
        }
    }

    private func endCapture() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = false
        if !HotKey.shared.register(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyMods) {
            hint = "Это сочетание занято системой или другим приложением — выберите другое."
        }
        AppDelegate.shared?.refreshStatusItem()
    }
}
