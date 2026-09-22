import AppKit
import SwiftUI
import MouseCore

extension RingApplication {
    var resolvedURL: URL? {
        if let bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        let savedURL = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: savedURL.path) ? savedURL : nil
    }
}

struct RingActionIcon: View {
    let action: RingAction
    let size: CGFloat

    var body: some View {
        switch action {
        case .mouse(let mouseAction):
            Image(systemName: mouseAction.symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size, height: size)
        case .application(let application):
            if let url = application.resolvedURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size, weight: .medium))
                    .frame(width: size, height: size)
            }
        }
    }
}
