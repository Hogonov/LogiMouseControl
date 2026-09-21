import Foundation
import MouseCore

struct CaptureRecovery: Codable {
    var wheel: UInt8?
    var thumb: [UInt8]?
    var buttons: [String: [UInt8]] = [:]
    var isEmpty: Bool { wheel == nil && thumb == nil && buttons.isEmpty }
}

/// A small child of the same app, sleeping on a pipe (no polling or files).
/// EOF after a crash returns owned controls to native HID. Normal exits send `clean`.
/// The recovery snapshot is delivered BEFORE each hardware diversion write.
final class CaptureGuardian {
    private var process: Process?
    private var input: Pipe?
    func checkpoint(_ recovery: CaptureRecovery) throws {
        if process == nil {
            guard !recovery.isEmpty else { return }
            guard let executable = Bundle.main.executableURL else { throw HIDFailure.safetyUnavailable }
            let child = Process(), pipe = Pipe()
            child.executableURL = executable; child.arguments = ["--recover-on-exit"]
            child.standardInput = pipe; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
            try child.run()
            process = child; input = pipe
        }
        guard process?.isRunning == true, let input else { throw HIDFailure.safetyUnavailable }
        var data = try JSONEncoder().encode(recovery); data.append(0x0a)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func finish(clean: Bool) {
        if clean { try? input?.fileHandleForWriting.write(contentsOf: Data("clean\n".utf8)) }
        try? input?.fileHandleForWriting.close()
        input = nil; process = nil
    }
    static func run() {
        var recovery: CaptureRecovery?
        var clean = false
        while let line = readLine() {
            if line == "clean" { clean = true; continue }
            if let data = line.data(using: .utf8), let state = try? JSONDecoder().decode(CaptureRecovery.self, from: data) { recovery = state; clean = false }
        }
        guard !clean, let recovery, !recovery.isEmpty else { return }
        let service = DeviceService()
        var finished = false
        service.onConnected = {
            service.restoreRecovery(recovery) { _ in
                finished = true; service.transport.stop(); CFRunLoopStop(CFRunLoopGetMain())
            }
        }
        service.transport.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            guard !finished else { return }
            finished = true; service.transport.stop(); CFRunLoopStop(CFRunLoopGetMain())
        }
        if !finished { CFRunLoopRun() }
        withExtendedLifetime(service) {}
    }
}
