import SwiftUI
#if SWIFT_PACKAGE
import RivetdeckCore
#endif

/// Small colored dot used for runtime and session status everywhere.
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7
    var pulsing = false
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulsing ? (pulse ? 0.35 : 1.0) : 1.0)
            .animation(pulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

extension RuntimeState {
    var dotColor: Color {
        switch self {
        case .stopped: return Tokens.Color.statusIdle
        case .starting: return Tokens.Color.statusWarning
        case .connected: return Tokens.Color.statusOK
        case .failed: return Tokens.Color.statusError
        }
    }
    var isLive: Bool {
        if case .starting = self { return true }
        return false
    }
}
