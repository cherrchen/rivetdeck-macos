import AppKit
import SwiftUI

/// Central design tokens. Colors and geometry track the DSH Web design platform
/// (DeepSeek blue brand, layered borders, folded turn process) expressed as
/// adaptive native colors.
enum Tokens {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let panel: CGFloat = 24
    }
    enum Sidebar {
        static let min: CGFloat = 264
        static let ideal: CGFloat = 280
        static let max: CGFloat = 420
    }
    enum Inspector {
        static let min: CGFloat = 300
        static let ideal: CGFloat = 340
        static let max: CGFloat = 480
    }
    enum Layout {
        static let contentMaxWidth: CGFloat = 760
    }
    enum Color {
        private static func adaptive(_ light: NSColor, _ dark: NSColor) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }
        private static func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
        }
        static let brand = adaptive(srgb(65, 118, 230), srgb(122, 170, 255))
        static let base = adaptive(srgb(255, 255, 255), srgb(21, 21, 23))
        static let inputSurface = adaptive(srgb(255, 255, 255), srgb(44, 44, 46))
        static let bubble = adaptive(srgb(237, 243, 254), srgb(44, 44, 46))
        static let codeBlock = adaptive(srgb(249, 250, 251), srgb(27, 27, 28))
        static let hoverFill = adaptive(srgb(38, 49, 72, 0.06), NSColor(white: 1, alpha: 0.08))
        static let borderL2 = adaptive(NSColor(white: 0, alpha: 0.10), NSColor(white: 1, alpha: 0.12))
        static let borderL3 = adaptive(NSColor(white: 0, alpha: 0.12), NSColor(white: 1, alpha: 0.16))
        static let borderL4 = adaptive(NSColor(white: 0, alpha: 0.16), NSColor(white: 1, alpha: 0.20))
        static let labelSecondary = adaptive(srgb(97, 102, 107), srgb(207, 211, 214))
        static let labelTertiary = adaptive(srgb(129, 133, 140), srgb(173, 178, 184))
        static let labelCaption = adaptive(srgb(173, 178, 184), srgb(129, 133, 140))
        static let statusOK = adaptive(srgb(34, 197, 94), srgb(34, 197, 94))
        static let statusWarning = adaptive(srgb(245, 158, 11), srgb(245, 158, 11))
        static let statusError = adaptive(srgb(236, 19, 19), srgb(242, 90, 90))
        static let statusIdle = adaptive(srgb(212, 212, 212), srgb(84, 85, 87))
        static let statusRunning = brand
        static let previewBadgeFill = adaptive(srgb(228, 237, 253), srgb(52, 65, 91))
    }
    enum Icon {
        static let brand = "bubble.left.and.bubble.right.fill"
        static let newSession = "square.and.pencil"
        static let workspace = "folder"
        static let settings = "gearshape"
        static let inspector = "sidebar.right"
        static let send = "arrow.up"
        static let diagnostics = "stethoscope"
        static let warning = "exclamationmark.triangle.fill"
        static let error = "exclamationmark.octagon.fill"
        static let activity = "bolt.horizontal"
        static let tool = "wrench.and.screwdriver"
        static let subagent = "person.2"
        static let turnEnded = "flag"
        static let approval = "hand.raised"
        static let resume = "arrow.uturn.forward.circle"
        static let disconnect = "power"
        static let connect = "cable.connector"
    }
}

/// Preview capsule badge used next to the wordmark.
struct PreviewBadge: View {
    var body: some View {
        Text("Preview")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Tokens.Color.labelSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Tokens.Color.previewBadgeFill, in: Capsule())
    }
}

extension View {
    /// Subtle bordered card used for the composer, inspector groups and notices.
    func cardStyle(padding: CGFloat = Tokens.Spacing.md) -> some View {
        self
            .padding(padding)
            .background(Tokens.Color.inputSurface, in: RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                    .strokeBorder(Tokens.Color.borderL2, lineWidth: 0.5)
            )
    }
}
