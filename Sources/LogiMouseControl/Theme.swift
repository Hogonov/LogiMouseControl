import SwiftUI
import MouseCore

/// The only place with colour literals. The interface is always dark; the accent comes from `Preferences.accent`.
enum Palette {
    static let canvas = Color(red: 0.07, green: 0.074, blue: 0.082)
    static let sidebar = Color(red: 0.088, green: 0.093, blue: 0.102)
    static let surface = Color(red: 0.114, green: 0.12, blue: 0.132)
    /// Raised block inside a surface, such as the status box in the sidebar.
    static let raised = Color.white.opacity(0.035)
    /// Sunken block inside a surface, such as the scroll test area.
    static let inset = Color.black.opacity(0.18)
    static let stroke = Color.white.opacity(0.07)
    /// Edge of the action ring over an arbitrary desktop.
    static let panelStroke = Color.white.opacity(0.15)
    static let hairline = Color.white.opacity(0.045)
    static let selection = Color.white.opacity(0.05)
    static let inactive = Color.white.opacity(0.62)
    static let inactiveDot = Color.white.opacity(0.18)
    static let warning = Color.orange
    /// Text on an accent fill; every accent is light enough for it (checked in MouseCoreChecks).
    static let onAccent = Color.black
}

extension AccentColor {
    var color: Color { Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue) }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentColor.mint.color
}

extension EnvironmentValues {
    /// Classic key instead of `@Entry`: the macOS 27 CLT ships SwiftUI without its macro plugin.
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

extension View {
    /// Applies the dark scheme and the chosen accent to a window or panel root.
    func appTheme(_ accent: AccentColor) -> some View {
        environment(\.accent, accent.color).tint(accent.color).preferredColorScheme(.dark)
    }
}

struct AccentPicker: View {
    @Binding var selection: AccentColor

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AccentColor.allCases) { accent in
                let selected = accent == selection
                Button { selection = accent } label: {
                    Circle().fill(accent.color).frame(width: 22, height: 22)
                        .overlay {
                            if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.onAccent) }
                        }
                        .padding(3)
                        .overlay(Circle().stroke(selected ? accent.color : Palette.stroke, lineWidth: selected ? 2 : 1))
                        .contentShape(Circle())
                }.buttonStyle(.plain)
                    .help(accent.title)
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
