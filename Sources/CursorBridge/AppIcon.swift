import AppKit

/// The logo, drawn in code so the app icon, the window and the menu bar share one source.
/// Coordinates are on a 256-point grid with y growing downwards.
enum AppIcon {
    private static let ground = NSColor(srgbRed: 0.086, green: 0.200, blue: 0.373, alpha: 1)
    private static let screen = NSColor(srgbRed: 0.157, green: 0.314, blue: 0.541, alpha: 1)
    private static let outline = NSColor(srgbRed: 0.910, green: 0.933, blue: 0.984, alpha: 1)
    private static let cursor = NSColor(srgbRed: 0.961, green: 0.647, blue: 0.141, alpha: 1)

    private static let displays = [
        NSRect(x: 40, y: 52, width: 80, height: 52),
        NSRect(x: 136, y: 52, width: 80, height: 52),
        NSRect(x: 84, y: 152, width: 88, height: 54),
    ]

    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            draw(scale: size / 256, detailed: size > 40)
            return true
        }
    }

    private static func draw(scale: CGFloat, detailed: Bool) {
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()

        ground.setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 240, height: 240), xRadius: 56, yRadius: 56).fill()

        for rect in displays {
            let path = NSBezierPath(roundedRect: detailed ? rect : rect.insetBy(dx: -4, dy: -4), xRadius: 6, yRadius: 6)
            if detailed {
                screen.setFill()
                path.fill()
            }
            path.lineWidth = detailed ? 6 : 16
            outline.setStroke()
            path.stroke()
        }
        guard detailed else { return }

        outline.setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 206, width: 116, height: 10), xRadius: 5, yRadius: 5).fill()

        let trail = NSBezierPath()
        trail.move(to: NSPoint(x: 58, y: 108))
        trail.curve(to: NSPoint(x: 98, y: 158), controlPoint1: NSPoint(x: 58, y: 140), controlPoint2: NSPoint(x: 76, y: 150))
        trail.lineWidth = 7
        trail.lineCapStyle = .round
        trail.setLineDash([2, 13], count: 2, phase: 0)
        cursor.setStroke()
        trail.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 100, y: 150))
        for point in [(100, 186), (109, 177), (116, 192), (123, 189), (116, 174), (128, 174)] {
            arrow.line(to: NSPoint(x: point.0, y: point.1))
        }
        arrow.close()
        arrow.lineJoinStyle = .round
        arrow.lineWidth = 4
        cursor.setFill()
        arrow.fill()
        ground.setStroke()
        arrow.stroke()
    }

    /// Two monitors over a laptop, as a template image so it follows light and dark menu bars.
    /// A small trail marks routing on; a dot marks missing Accessibility access.
    static func menuBarImage(for status: RoutingStatus) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            NSColor.black.setStroke()
            for rect in [NSRect(x: 1, y: 1, width: 9, height: 6), NSRect(x: 12, y: 1, width: 9, height: 6), NSRect(x: 6, y: 10, width: 10, height: 5)] {
                let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                path.lineWidth = 1.6
                path.stroke()
            }
            switch status {
            case .running:
                let trail = NSBezierPath()
                trail.move(to: NSPoint(x: 3.5, y: 8))
                trail.line(to: NSPoint(x: 3.5, y: 11))
                trail.line(to: NSPoint(x: 5, y: 11))
                trail.lineWidth = 1.6
                trail.stroke()
            case .needsAccess:
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 15, y: 9.5, width: 6, height: 6)).fill()
            case .off:
                break
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
