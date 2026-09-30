import AppKit
import CursorBridgeCore

enum DisplayProvider {
    @MainActor
    static func current() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        let names = Dictionary(
            NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, withoutDuplicateSuffix(screen.localizedName)) } },
            uniquingKeysWith: { first, _ in first }
        )

        var seenKeys = Set<String>()
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .sorted { (CGDisplayBounds($0).minX, CGDisplayBounds($0).minY) < (CGDisplayBounds($1).minX, CGDisplayBounds($1).minY) }
            .map { id in
                var key = stableKey(for: id)
                if !seenKeys.insert(key).inserted {
                    key += "#\(CGDisplayUnitNumber(id))"
                    seenKeys.insert(key)
                }
                return Display(
                    id: key,
                    displayID: id,
                    name: names[id] ?? "Display \(id)",
                    frame: CGDisplayBounds(id),
                    physicalSize: orientedPhysicalSize(of: id)
                )
            }
    }

    /// macOS tells identical monitors apart as "Name (1)", "Name (2)"; those numbers clash with the app's own.
    private static func withoutDuplicateSuffix(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s\(\d+\)$"#, with: "", options: .regularExpression)
    }

    /// Display IDs change across reboots and reconnects; the ColorSync UUID survives them.
    private static func stableKey(for id: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// Rotated panels can report their unrotated physical size.
    private static func orientedPhysicalSize(of id: CGDirectDisplayID) -> CGSize {
        let size = CGDisplayScreenSize(id)
        let bounds = CGDisplayBounds(id)
        guard size.width > 0, size.height > 0 else { return .zero }
        if (size.width > size.height) != (bounds.width > bounds.height) {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
