import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 12) {
                ModelCard(model: state.asr, onStart: { state.startModel(state.asr) }, onStop: { state.stopModel(state.asr) },
                          picker: AnyView(ASREnginePicker(settings: state.settings, state: state)))
                ModelCard(model: state.llm, onStart: { state.startModel(state.llm) }, onStop: { state.stopModel(state.llm) })
            }
            recordBar
            if let n = state.notice {
                Label(n, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            TranscriptView(state: state)
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 600)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("fast-whisper").font(.system(size: 22, weight: .semibold))
            Spacer()
            Text("Микрофон: \(state.micStatus)").font(.caption).foregroundStyle(.secondary)
            if state.settings.autoPaste {
                if state.axTrusted {
                    Text("· Вставка: разрешена").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Разрешить вставку текста") { Paster.askAgain() }
                        .font(.caption).foregroundStyle(.orange)
                        .help("Нужно разрешение «Универсальный доступ», чтобы вставлять текст туда, где стоит курсор")
                }
            }
            Button {
                AppDelegate.shared?.showSettings()
            } label: { Label("Настройки", systemImage: "gearshape") }
        }
    }

    private var recordBar: some View {
        HStack(spacing: 14) {
            Button {
                state.toggleRecording()
            } label: {
                Label(state.isRecording ? "Остановить" : "Начать запись",
                      systemImage: state.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .frame(minWidth: 150)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(state.isRecording ? .red : .accentColor)

            LevelMeter(level: state.level, active: state.isRecording)
                .frame(width: 140, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Горячая клавиша: \(state.settings.hotKeyDisplay) · язык: \(state.settings.languageName)").font(.callout)
                Text(state.isRecording ? "Идёт запись — фразы отправляются в модель после каждой паузы"
                                       : "Нажмите, чтобы начать запись, и ещё раз — чтобы остановить")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
