// MARK: - Model card

/// Recognition engine picker. Unload the current model before changing the
/// engine, then load the selected model.

import SwiftUI
import AppKit

struct ASREnginePicker: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Модель", selection: $settings.asrEngine) {
                ForEach(Settings.asrEngines, id: \.code) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
            .disabled(state.asr.isRunning)
            .onChange(of: settings.asrEngine) {
                if !state.asr.isRunning { state.asr.subtitle = settings.asrEngineInfo.subtitle }
            }
            Text(state.asr.isRunning ? "Чтобы сменить модель — выгрузите её" : settings.asrEngineInfo.hint)
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let w = state.asrLanguageWarning {
                Text(w).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ModelCard: View {
    @ObservedObject var model: ModelProcess
    var onStart: () -> Void
    var onStop: () -> Void
    var picker: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusDot
                Text(model.title).font(.headline)
                Spacer()
            }
            Text(model.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let picker { picker }

            ProgressView(value: model.progress)
                .tint(model.status == .failed ? .red : model.status == .ready ? .green : .accentColor)

            Text(model.stage).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    Text("Оперативная память").foregroundStyle(.secondary)
                    Text(model.isRunning ? "\(mb(model.memoryMB)) из ~\(mb(model.expectedMB))" : "—").monospacedDigit()
                }
                GridRow {
                    Text("Пик").foregroundStyle(.secondary)
                    Text(model.peakMB > 0 ? mb(model.peakMB) : "—").monospacedDigit()
                }
                GridRow {
                    Text("Загрузка").foregroundStyle(.secondary)
                    Text(loadText).monospacedDigit()
                }
            }
            .font(.caption)

            if let e = model.lastError {
                Text(e).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.isRunning {
                    Button("Выгрузить", action: onStop)
                } else {
                    Button(model.status == .failed ? "Повторить" : "Запустить", action: onStart)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    private var statusDot: some View {
        let c: Color = switch model.status {
        case .ready: .green
        case .loading: .orange
        case .failed: .red
        case .stopped: .gray
        }
        return Circle().fill(c).frame(width: 9, height: 9)
    }

    private var loadText: String {
        if let s = model.loadSeconds { return String(format: "%.1f с", s) }
        if model.status == .loading { return String(format: "%.1f с…", model.elapsed) }
        return "—"
    }

    private func mb(_ v: Double) -> String {
        v >= 1024 ? String(format: "%.2f ГБ", v / 1024) : String(format: "%.0f МБ", v)
    }
}

struct LevelMeter: View {
    var level: Float
    var active: Bool
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .separatorColor))
                Capsule().fill(active ? Color.green : Color.gray)
                    .frame(width: g.size.width * CGFloat(min(1, Double(level) * 12)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
    }
}
