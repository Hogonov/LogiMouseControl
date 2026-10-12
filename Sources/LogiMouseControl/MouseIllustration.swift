import SwiftUI
import MouseCore

/// The same local product renders are used for the overview and button map.
enum MouseArtwork {
    static let manifest: MouseArtworkManifest? = decode("manifest.json")
    static let metadata: MouseArtworkMetadata? = decode("core_metadata.json")
    private static var images: [String: NSImage] = [:]

    private static func decode<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "DeviceImages"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func image(extendedModelID: UInt8?, buttons: Bool) -> NSImage? {
        guard let name = manifest?.imageName(extendedModelID: extendedModelID, buttons: buttons) else { return nil }
        if let image = images[name] { return image }
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "DeviceImages"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }
}

struct MouseIllustration: View {
    var extendedModelID: UInt8?
    var buttons = false
    var body: some View {
        if let image = MouseArtwork.image(extendedModelID: extendedModelID, buttons: buttons) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .accessibilityLabel("MX Master 4")
        } else {
            Image(systemName: "computermouse").resizable().scaledToFit().foregroundStyle(.secondary)
                .accessibilityLabel("MX Master 4: изображение недоступно")
        }
    }
}

struct MouseButtonMap: View {
    let controls: [MouseControl]
    let extendedModelID: UInt8?
    @Binding var selectedID: UInt16?
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geometry in
            if let image = MouseArtwork.image(extendedModelID: extendedModelID, buttons: true) {
                let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                let width = image.size.width * scale
                let height = image.size.height * scale
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image).resizable().interpolation(.high).frame(width: width, height: height)
                        .accessibilityHidden(true)
                    ForEach(controls) { control in
                        if let point = MouseArtwork.metadata?.buttons?.normalizedPoint(for: control.id, pngWidth: image.size.width) {
                            Button { selectedID = control.id } label: {
                                Circle().fill(accent.opacity(selectedID == control.id ? 0.3 : 0.14)).frame(width: 32, height: 32)
                                    .overlay(Circle().fill(selectedID == control.id ? .white : accent).frame(width: 13, height: 13)
                                        .overlay(Circle().stroke(Palette.onAccent.opacity(0.85), lineWidth: 2)))
                                    .overlay(Circle().stroke(accent.opacity(selectedID == control.id ? 1 : 0), lineWidth: 2))
                                    .contentShape(Circle())
                            }.buttonStyle(.plain)
                                .position(x: point.x * width, y: point.y * height)
                                .help(control.name)
                                .accessibilityLabel(control.name)
                                .accessibilityValue(selectedID == control.id ? "Выбрана" : "")
                        }
                    }
                }.frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                MouseIllustration(extendedModelID: extendedModelID, buttons: true)
            }
        }
    }
}

struct ButtonAssignmentsView: View {
    let controls: [MouseControl]
    let extendedModelID: UInt8?
    @Binding var assignments: [String: MouseAction]
    @Binding var gestures: [String: GestureActions]
    let changed: () -> Void
    let testAction: (MouseAction) -> Void
    /// Only for the artwork preview; the window starts with the first control.
    var initialSelectedID: UInt16? = nil
    @ViewState<UInt16?> private var selectedID: UInt16? = nil
    @Environment(\.accent) private var accent
    private var selected: MouseControl? { controls.first { $0.id == (selectedID ?? initialSelectedID) } ?? controls.first }

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 14) {
                MouseButtonMap(controls: controls, extendedModelID: extendedModelID,
                               selectedID: Binding(get: { selected?.id }, set: { selectedID = $0 }))
                    .frame(width: 280, height: 438)
                Text("Нажмите на точку на мыши").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                if let selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("НАЗНАЧЕНИЕ КНОПКИ").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(accent)
                        Text(selected.name).font(.system(size: 20, weight: .semibold))
                        Picker("Действие", selection: Binding(get: { assignments[String(selected.id)] ?? .system }, set: {
                            assignments[String(selected.id)] = $0; changed()
                        })) {
                            ForEach(MouseAction.allCases.filter { $0 != .gestures || selected.rawXY }) { action in
                                Text(action.title).tag(action)
                            }
                        }.labelsHidden().frame(maxWidth: .infinity)
                        let action = assignments[String(selected.id)] ?? .system
                        if action == .gestures {
                            GestureDirectionsView(actions: Binding(get: { gestures[String(selected.id)] ?? GestureActions() },
                                                                   set: { gestures[String(selected.id)] = $0; changed() }))
                        } else if action != .system && action != .none {
                            Button("Проверить действие", systemImage: "play") { testAction(action) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    VStack(spacing: 2) {
                        ForEach(controls) { control in
                            let action = assignments[String(control.id)] ?? .system
                            Button { selectedID = control.id } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(selected.id == control.id ? accent : Palette.inactiveDot).frame(width: 6, height: 6)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(control.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                        Text(action.title).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: action.symbol).font(.system(size: 13)).foregroundStyle(.secondary)
                                }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selected.id == control.id ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Action per direction for a control assigned to «Жесты».
private struct GestureDirectionsView: View {
    @Binding var actions: GestureActions

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("НАПРАВЛЕНИЯ ЖЕСТА").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(GestureDirection.allCases) { direction in
                HStack(spacing: 8) {
                    Image(systemName: direction.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 16)
                    Text(direction.title).font(.system(size: 12)).frame(width: 62, alignment: .leading)
                    Picker(direction.title, selection: $actions[direction]) {
                        ForEach(MouseAction.gestureChoices) { action in Text(action.title).tag(action) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            Text("Удерживайте кнопку, сдвиньте мышь и отпустите. «Нажатие» — отпустить кнопку без движения.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
