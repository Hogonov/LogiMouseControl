import SwiftUI
import AppKit
import MouseCore

final class RingController {
    private var panel: NSPanel?
    private var outsideMonitor: Any?
    private var escapeMonitor: Any?
    private var lastPulse = 0.0
    func show(actions: [RingAction], execute: @escaping (RingAction) -> Void, pulse: @escaping () -> Void) {
        if panel != nil { close(); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 340), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: ActionRingView(actions: actions, select: { [weak self] action in self?.close(); execute(action) }, cancel: { [weak self] in self?.close() }, hover: { [weak self] in
            let now = ProcessInfo.processInfo.systemUptime
            if now - (self?.lastPulse ?? 0) > 0.08 { self?.lastPulse = now; pulse() }
        }))
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let x = max(bounds.minX, min(bounds.maxX - 340, point.x - 170))
        let y = max(bounds.minY, min(bounds.maxY - 340, point.y - 170))
        panel.setFrameOrigin(NSPoint(x: x, y: y)); panel.orderFrontRegardless()
        self.panel = panel
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }; return event
        }
    }
    func close() {
        panel?.orderOut(nil); panel = nil
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }; outsideMonitor = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
    }
}
struct ActionRingView: View {
    let actions: [RingAction]
    let select: (RingAction) -> Void
    let cancel: () -> Void
    let hover: () -> Void
    @ViewState<Int?> private var hovered: Int?
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1)).padding(9)
            Button(action: cancel) { VStack(spacing: 6) { Image(systemName: "xmark").font(.title3); Text("Закрыть").font(.caption) }.foregroundStyle(.secondary).frame(width: 78, height: 78).background(.quaternary, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Закрыть кольцо действий")
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                let angle = Double(index) * .pi / 3 - .pi / 2
                Button { select(action) } label: {
                    VStack(spacing: 8) { Image(systemName: action.symbol).font(.system(size: 23, weight: .medium)); Text(action.title).font(.system(size: 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center) }
                        .frame(width: 82, height: 76).foregroundStyle(hovered == index ? Color.black : Color.primary)
                        .background(hovered == index ? Color.mint : .clear, in: RoundedRectangle(cornerRadius: 21))
                }.buttonStyle(.plain).offset(x: cos(angle) * 112, y: sin(angle) * 112)
                    .onHover { inside in hovered = inside ? index : nil; if inside { hover() } }
            }
        }.frame(width: 340, height: 340).preferredColorScheme(.dark)
    }
}
