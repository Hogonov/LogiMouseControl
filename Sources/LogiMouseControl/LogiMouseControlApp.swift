import SwiftUI
import AppKit

// Use the property-wrapper type explicitly: macOS 27 CLT ships State macros
// without the SwiftUIMacros plugin, while the stable wrapper remains supported.
typealias ViewState<Value> = SwiftUI.State<Value>

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
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
            MainView().environmentObject(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1060, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("MX Master 4", systemImage: model.active ? "computermouse.fill" : "computermouse") {
            MenuContent(model: model)
        }
    }
}
struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("MX Master 4 · \(model.device.battery.map { "\($0)%" } ?? "—")")
        Text(model.status)
        Divider()
        Button("Открыть настройки") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.paused ? "Продолжить обработку" : "Приостановить обработку") { model.togglePause() }
        Button("Кольцо действий") { model.showRing() }.disabled(!model.accessibility)
        Divider()
        Button("Завершить Logi Mouse Control") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
