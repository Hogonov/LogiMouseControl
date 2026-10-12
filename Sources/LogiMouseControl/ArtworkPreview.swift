import AppKit
import SwiftUI
import MouseCore

/// Explicit developer-only rendering check. Does not create AppModel, access HID,
/// load/save user preferences, or execute actions. Uses the shipping SwiftUI views.
@MainActor
func renderArtworkPreview(to directory: URL) throws {
    _ = NSApplication.shared
    let controls = [MouseControl(id: 0x52, flags: 0x20), MouseControl(id: 0xc4, flags: 0x120),
                    MouseControl(id: 0x56, flags: 0x120), MouseControl(id: 0x53, flags: 0x120),
                    MouseControl(id: 0xc3, flags: 0x120), MouseControl(id: 0x1a0, flags: 0x120)]
    let assignments: [String: MouseAction] = ["82": .spotlight, "195": .gestures, "196": .system,
                                              "83": .back, "86": .forward, "416": .ring]
    func buttons(selecting id: UInt16? = nil) -> some View {
        ButtonAssignmentsView(controls: controls, extendedModelID: 1, assignments: .constant(assignments),
                              gestures: .constant([:]), changed: {}, testAction: { _ in }, initialSelectedID: id)
            .padding(20).frame(width: 676, height: 580, alignment: .top)
            .background(Color(red: 0.105, green: 0.12, blue: 0.125)).preferredColorScheme(.dark)
    }
    let overview = MouseIllustration(extendedModelID: 1).padding(.vertical, 15)
        .frame(width: 220, height: 250).padding(24)
        .background(Color(red: 0.11, green: 0.16, blue: 0.14)).preferredColorScheme(.dark)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try render(buttons(), size: NSSize(width: 676, height: 580), to: directory.appendingPathComponent("buttons.png"))
    try render(buttons(selecting: 0xc3), size: NSSize(width: 676, height: 580), to: directory.appendingPathComponent("gestures.png"))
    try render(overview, size: NSSize(width: 268, height: 298), to: directory.appendingPathComponent("overview.png"))
}

@MainActor
private func render<V: View>(_ view: V, size: NSSize, to url: URL) throws {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw HIDFailure.malformed }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw HIDFailure.malformed }
    try png.write(to: url)
}
