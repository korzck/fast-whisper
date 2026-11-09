import SwiftUI

func composeTranscript(_ state: AppState, session: Int?) -> Text {
    var t = Text("")
    var last = -1
    for (i, s) in state.segments.enumerated() where session == nil || s.session == session {
        if last != -1 { t = t + Text(s.session == last ? " " : "\n\n") }
        last = s.session
        switch s.state {
        case .recognizing: t = t + Text(s.raw.isEmpty ? "…" : s.raw).foregroundColor(.secondary)
        case .correcting: t = t + Text(s.raw).foregroundColor(.secondary)
        case .done: t = t + Text(state.displayText(at: i))
        }
    }
    if !state.partialText.isEmpty {
        if last != -1 { t = t + Text(last == state.session ? " " : "\n\n") }
        t = t + Text(state.partialText).foregroundColor(.secondary).italic()
    }
    return t
}
