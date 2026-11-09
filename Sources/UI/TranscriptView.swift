// MARK: - Transcript

import SwiftUI
import AppKit

struct TranscriptView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Текст").font(.headline)
                if let last = state.segments.last(where: { $0.state == .done }) {
                    Text(stats(last)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.copyAll() } label: { Label("Копировать", systemImage: "doc.on.doc") }
                    .disabled(state.segments.isEmpty)
                Button { state.clear() } label: { Label("Очистить", systemImage: "trash") }
                    .disabled(state.segments.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if state.segments.isEmpty && state.partialText.isEmpty {
                            Text("Здесь появится распознанный и исправленный текст.")
                                .foregroundStyle(.secondary)
                        } else {
                            composed.textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                .onChange(of: state.segments.count) { proxy.scrollTo("end") }
                .onChange(of: state.partialText) { proxy.scrollTo("end") }
            }
            Text("Серым курсивом — то, что вы говорите прямо сейчас; серым — распознанная фраза; обычным — исправленная LLM.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Render completed segments normally and uncorrected segments in gray.
    private var composed: Text { composeTranscript(state, session: nil) }

    private func stats(_ s: Segment) -> String {
        var parts = [String(format: "фраза %.1f с", s.duration)]
        if let a = s.asrMs { parts.append("\(state.loadedASREngine == "gigaam" ? "GigaAM" : "Whisper") \(a) мс") }
        if let l = s.llmMs { parts.append("Gemma \(l) мс") }
        return parts.joined(separator: " · ")
    }
}
