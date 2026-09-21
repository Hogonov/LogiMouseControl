import Foundation
import IOKit.hid
import MouseCore

/// IOKit callbacks live on the main run loop. Blocking transactions run only on
/// DeviceService.queue. One outstanding request, strict response matching, bounded wait.
final class HIDTransport {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let condition = NSCondition()
    private var pending: HIDPacket?
    private var reply: Result<[UInt8], HIDFailure>?
    private var softwareID: UInt8 = 1
    private var reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onEvent: ((HIDPacket) -> Void)?
    var onStatus: ((String) -> Void)?

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard manager == nil else { retry(); return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // Exact model only. Never seize the mouse; standard HID input stays available.
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046d, kIOHIDProductIDKey: 0xb042] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess { onStatus?(HIDFailure.io(result).localizedDescription) }
        retry()
    }
    func retry() {
        guard device == nil, let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices { attach(candidate) }
    }
    private func attach(_ candidate: IOHIDDevice) {
        guard device == nil else { return }
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { onStatus?(HIDFailure.io(result).localizedDescription); return }
        condition.lock(); device = candidate; condition.unlock()
        IOHIDDeviceRegisterInputReportCallback(candidate, reportBuffer, 512, { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context else { return }
            let owner = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
            owner.receive(Array(UnsafeBufferPointer(start: report, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        onConnect?()
    }
    private func removed(_ candidate: IOHIDDevice) {
        guard let device, CFEqual(candidate, device) else { return }
        detach()
        onDisconnect?()
    }
    private func detach() {
        condition.lock()
        let old = device; device = nil
        reply = .failure(.disconnected); condition.broadcast()
        condition.unlock()
        if let old {
            IOHIDDeviceUnscheduleFromRunLoop(old, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(old, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
    func stop() {
        detach()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }
    private func receive(_ bytes: [UInt8]) {
        guard let packet = HIDPacket.decode(bytes) else { return }
        condition.lock()
        if let pending, let response = packet.response(to: pending) {
            reply = response; condition.broadcast(); condition.unlock(); return
        }
        condition.unlock()
        if packet.device == 0xff && packet.softwareID == 0 { onEvent?(packet) }
    }
    func request(feature: UInt8, function: UInt8, payload: [UInt8] = []) throws -> [UInt8] {
        precondition(!Thread.isMainThread, "HID requests cannot block UI callbacks")
        condition.lock()
        guard let device else { condition.unlock(); throw HIDFailure.disconnected }
        softwareID = softwareID % 15 + 1
        let request = HIDPacket(feature: feature, function: function, softwareID: softwareID, payload: payload)
        pending = request; reply = nil
        condition.unlock()
        let bytes = request.bytes
        let result = bytes.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, $0.baseAddress!, bytes.count) }
        condition.lock()
        defer { pending = nil; reply = nil; condition.unlock() }
        guard result == kIOReturnSuccess else { throw HIDFailure.io(result) }
        let deadline = Date(timeIntervalSinceNow: 0.8)
        while reply == nil {
            if !condition.wait(until: deadline) { throw HIDFailure.timeout }
        }
        return try reply!.get()
    }
    func notify(feature: UInt8, function: UInt8, payload: [UInt8]) throws {
        condition.lock(); let current = device; condition.unlock()
        guard let current else { throw HIDFailure.disconnected }
        let bytes = HIDPacket(feature: feature, function: function, softwareID: 1, payload: payload).bytes
        let result = bytes.withUnsafeBufferPointer { IOHIDDeviceSetReport(current, kIOHIDReportTypeOutput, 0x11, $0.baseAddress!, bytes.count) }
        guard result == kIOReturnSuccess else { throw HIDFailure.io(result) }
    }
}
