import AppKit
import MouseCore

@main
struct AppEntry {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-artwork-preview"), CommandLine.arguments.count > index + 1 {
            do { try renderArtworkPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { print("Не удалось создать предпросмотр: \(error.localizedDescription)"); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--recover-on-exit") { CaptureGuardian.run(); return }
        if CommandLine.arguments.contains("--diagnose") { diagnose(); return }
        LogiMouseControlApp.main()
    }
    /// Read-only, explicit developer diagnostic. No report/event logging or writes.
    private static func diagnose() {
        let service = DeviceService()
        var finished = false
        service.onSnapshot = { state in
            guard state.connected, !finished else { return }; finished = true
            let report: [String: Any] = [
                "model": "MX Master 4", "transport": "Bluetooth", "connected": true,
                "features": state.features.keys.sorted().map { String(format: "%04X", $0) },
                "extendedModelID": state.extendedModelID as Any? ?? NSNull(),
                "battery": state.battery as Any? ?? NSNull(), "dpi": state.dpi as Any? ?? NSNull(),
                "dpiValues": state.dpiValues, "wheel": state.wheelMode?.rawValue as Any? ?? NSNull(),
                "threshold": state.threshold, "torque": state.torque as Any? ?? NSNull(),
                "haptics": state.haptics as Any? ?? NSNull(), "intensity": state.intensity,
                "controls": state.controls.map { ["name": $0.name, "cid": Int($0.id), "rawXY": $0.rawXY] as [String: Any] },
                "warnings": state.warnings,
                "accessibility": AXIsProcessTrusted(), "inputMonitoring": CGPreflightListenEventAccess()
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            service.transport.stop(); CFRunLoopStop(CFRunLoopGetMain())
        }
        service.onError = { message in
            guard !finished else { return }; finished = true
            print("Диагностика: \(message)"); service.transport.stop(); CFRunLoopStop(CFRunLoopGetMain())
        }
        service.transport.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            guard !finished else { return }; finished = true
            print("MX Master 4 не ответила. Проверьте подключение и Мониторинг ввода.")
            service.transport.stop(); CFRunLoopStop(CFRunLoopGetMain())
        }
        if !finished { CFRunLoopRun() }
        withExtendedLifetime(service) {}
    }
}
