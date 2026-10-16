import AppKit

/// The logo, drawn in code so the app icon, the window and the menu bar share one source: two screens
/// stepped diagonally, the cursor crossing at the step. Coordinates are on a 256-point grid, y downwards.
enum AppIcon {
    private static let ground = NSColor(srgbRed: 0.231, green: 0.184, blue: 0.420, alpha: 1)
    private static let screen = NSColor(srgbRed: 0.310, green: 0.271, blue: 0.565, alpha: 1)
    private static let outline = NSColor(srgbRed: 0.937, green: 0.918, blue: 0.988, alpha: 1)
    private static let cursor = NSColor(srgbRed: 1.000, green: 0.624, blue: 0.263, alpha: 1)

    /// Fewer, heavier strokes as the icon shrinks, so it stays legible down to 16 px.
    private enum Detail { case full, medium, small }

    static func image(size: CGFloat) -> NSImage {
        let detail: Detail = size > 40 ? .full : size > 24 ? .medium : .small
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            draw(scale: size / 256, detail: detail)
            return true
        }
    }

    private static func draw(scale: CGFloat, detail: Detail) {
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()

        ground.setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 240, height: 240), xRadius: 56, yRadius: 56).fill()

        let screens = detail == .small
            ? [NSRect(x: 30, y: 40, width: 124, height: 84), NSRect(x: 102, y: 132, width: 124, height: 84)]
            : [NSRect(x: 34, y: 42, width: 120, height: 80), NSRect(x: 104, y: 134, width: 120, height: 80)]
        for rect in screens {
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            if detail == .full {
                screen.setFill()
                path.fill()
            }
            path.lineWidth = switch detail {
            case .full: 8
            case .medium: 18
            case .small: 26
            }
            outline.setStroke()
            path.stroke()
        }

        let points: [(CGFloat, CGFloat)]
        switch detail {
        case .full: points = [(116, 100), (116, 168), (134, 150), (148, 180), (162, 174), (148, 144), (174, 144)]
        case .medium: points = [(112, 90), (112, 178), (136, 154), (152, 190), (170, 182), (154, 146), (188, 146)]
        case .small: return
        }
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: points[0].0, y: points[0].1))
        for point in points.dropFirst() {
            arrow.line(to: NSPoint(x: point.0, y: point.1))
        }
        arrow.close()
        cursor.setFill()
        arrow.fill()
        if detail == .full {
            arrow.lineJoinStyle = .round
            arrow.lineWidth = 6
            ground.setStroke()
            arrow.stroke()
        }
    }

    /// The two stepped screens as a template image, so it follows light and dark menu bars.
    /// Routing off dims it; missing Accessibility access adds a dot.
    static func menuBarImage(for status: RoutingStatus) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            let ink = NSColor.black.withAlphaComponent(status == .off ? 0.4 : 1)
            ink.setStroke()
            for rect in [NSRect(x: 1, y: 1, width: 11, height: 7), NSRect(x: 9, y: 8, width: 11, height: 7)] {
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2)
                path.lineWidth = 1.6
                path.stroke()
            }
            if status == .needsAccess {
                ink.setFill()
                NSBezierPath(ovalIn: NSRect(x: 16, y: 0, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Writes the PNGs `iconutil` turns into the bundle's AppIcon.icns.
    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                guard let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ) else { throw CocoaError(.fileWriteUnknown) }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                // Size the drawing by points, so the 16 pt @2x file keeps the simplified small design.
                image(size: CGFloat(points)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}
