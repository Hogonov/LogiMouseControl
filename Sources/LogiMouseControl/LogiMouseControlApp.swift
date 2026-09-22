import SwiftUI
import AppKit

// Use the property-wrapper type explicitly: macOS 27 CLT ships State macros
// without the SwiftUIMacros plugin, while the stable wrapper remains supported.
typealias ViewState<Value> = SwiftUI.State<Value>

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var openMainWindow: (() -> Void)?

    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard openMainWindow != nil else { return true }
        showSettings()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct LogiMouseControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Logi Mouse Control", id: "main") {
            MainWindowContent(model: model, delegate: delegate)
        }
        .defaultSize(width: 1060, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("MX Master 4", systemImage: model.active ? "computermouse.fill" : "computermouse") {
            MenuContent(model: model, openSettings: delegate.showSettings)
        }
    }
}
private struct MainWindowContent: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainView().environmentObject(model)
            .background(MainWindowCloseObserver())
            .onAppear {
                delegate.model = model
                // Keep the scene action available after the window closes.
                delegate.openMainWindow = { [openWindow] in openWindow(id: "main") }
                NSApp.setActivationPolicy(.regular)
            }
    }
}

// SwiftUI can retain window content after closing, so onDisappear is not a
// reliable close callback. Observe only the settings window, not menu/ring panels.
private struct MainWindowCloseObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> CloseObserverView { CloseObserverView() }
    func updateNSView(_ nsView: CloseObserverView, context: Context) {}

    final class CloseObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window
            )
        }

        @objc private func windowWillClose(_ notification: Notification) {
            NSApp.setActivationPolicy(.accessory)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    var body: some View {
        Text("MX Master 4 · \(model.device.battery.map { "\($0)%" } ?? "—")")
        Text(model.status)
        Divider()
        Button("Открыть настройки", action: openSettings)
        Button(model.paused ? "Продолжить обработку" : "Приостановить обработку") { model.togglePause() }
        Button("Кольцо действий") { model.showRing() }.disabled(!model.accessibility)
        Divider()
        Button("Завершить Logi Mouse Control") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
