import Combine

/// Transient settings-window state; never persisted in user preferences.
/// StateObject keeps this object alive across SwiftUI view reconstruction without
/// depending on the SwiftUIMacros.StateMacro plugin introduced in newer SDKs.
final class ShortcutCaptureState: ObservableObject {
    @Published var capturing = false
    @Published var monitor: Any?
    @Published var hint = ""
}
