import AppKit

/// Image helpers for clipboard capture: PNG encoding and thumbnail
/// generation. See ARCHITECTURE.md §4.3.
enum ImageProcessing {
    /// Full-resolution PNG encoding of a bitmap.
    static func pngData(from rep: NSBitmapImageRep) -> Data? {
        rep.representation(using: .png, properties: [:])
    }

    /// A downscaled PNG no larger than `maxDimension` on its longer edge,
    /// used as the history list thumbnail. Returns nil if the bitmap is empty.
    static func thumbnailPNGData(
        from rep: NSBitmapImageRep,
        maxDimension: Int = 128
    ) -> Data? {
        let sourceWidth = rep.pixelsWide
        let sourceHeight = rep.pixelsHigh
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = min(1.0, Double(maxDimension) / Double(longestEdge))
        let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))

        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        target.size = NSSize(width: targetWidth, height: targetHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: target) else {
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.flushGraphics()

        return target.representation(using: .png, properties: [:])
    }
}
