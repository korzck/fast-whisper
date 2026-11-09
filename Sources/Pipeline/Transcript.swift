import AppKit
import Combine

/// One recognized speech segment.
struct Segment: Identifiable {
    enum State { case recognizing, correcting, done }
    let id: Int
    let session: Int
    let duration: Double
    var state: State = .recognizing
    var raw = ""
    var final = ""
    var asrMs: Int?
    var llmMs: Int?
    var text: String { state == .done ? final : raw }
}

/// Presentation state for the floating overlay.
enum OverlayPhase: Equatable {
    case hidden, recording, finishing, inserted, clipboard, copied, empty
    var isFinal: Bool { self == .inserted || self == .clipboard || self == .copied || self == .empty }
    var title: String {
        switch self {
        case .hidden: return ""
        case .recording: return "Запись · " + AppState.shared.settings.languageName
        case .finishing: return "Доделываю последнюю фразу…"
        case .inserted: return "Вставлено"
        case .clipboard: return "Скопировано в буфер обмена"
        case .copied: return "Нет доступа к вставке — текст в буфере, нажмите ⌘V"
        case .empty: return "Ничего не распознано"
        }
    }
}
