import Foundation

public enum MouseIdentity {
    /// HID++ DeviceInformation (0x0003), function 0. No unique identifiers retained.
    public static func extendedModelID(from payload: [UInt8]) throws -> UInt8 {
        guard payload.count >= 15 else { throw HIDFailure.malformed }
        return payload[13]
    }
}

/// Logitech's resource catalog, as used by OpenLogi. Images are bundled locally.
public struct MouseArtworkManifest: Decodable {
    public struct Resource: Decodable {
        public let key: String
        public let src: String
    }
    public struct Variant: Decodable {
        public let modelId: String
        public let resources: [Resource]
    }
    public let devices: [Variant]
    public let resources: [Resource]

    public func imageName(extendedModelID: UInt8?, buttons: Bool) -> String? {
        // White is the owner's declared colour, also used before the first connection.
        let ext = extendedModelID ?? 1
        let model = ext == 0 ? "2b042" : "2b042_ext\(ext)"
        let key = buttons ? "device_buttons_image" : "device_image"
        return devices.first { $0.modelId == model }?.resources.first { $0.key == key }?.src
            ?? resources.first { $0.key == key }?.src
    }
}

public struct MouseArtworkMetadata: Decodable {
    public struct Point: Decodable { public let x: Double; public let y: Double }
    public struct Size: Decodable { public let width: Double; public let height: Double }
    public struct Assignment: Decodable {
        public let slotId: String
        public let marker: Point
        public var controlID: UInt16? {
            guard let suffix = slotId.components(separatedBy: "_c").last, suffix != slotId else { return nil }
            return UInt16(suffix)
        }
    }
    public struct ImageMetadata: Decodable {
        public let key: String
        public let origin: Size
        public let assignments: [Assignment]?

        /// Markers use percentages of the silhouette, not of the padded PNG.
        public func normalizedPoint(for controlID: UInt16, pngWidth: Double) -> (x: Double, y: Double)? {
            guard pngWidth > 0, let marker = assignments?.first(where: { $0.controlID == controlID })?.marker else { return nil }
            let width = min(origin.width, pngWidth) / pngWidth
            return ((1 - width) / 2 + marker.x / 100 * width, marker.y / 100)
        }
    }
    public let images: [ImageMetadata]
    public var buttons: ImageMetadata? { images.first { $0.key == "device_buttons_image" } }
}
