// Compile-only probe for the state ownership and bindings used by the app.
import SwiftUI
import Combine

private final class ProbeState: ObservableObject {
    @Published var enabled = false
    @Published var message = ""
    @Published var monitor: Any?
}

private struct SwiftUIStateProbe: View {
    @StateObject private var state = ProbeState()

    var body: some View {
        VStack {
            Toggle("Probe", isOn: $state.enabled)
            TextField("Message", text: $state.message)
            Button("Reset") { reset() }
        }
    }

    private func reset() {
        state.enabled = false
        state.message = ""
        state.monitor = nil
    }
}
