import ImageIO
import AppKit

/// Une image PNG carrée prête à être écrite dans la table favicon_bitmaps.
nonisolated struct FaviconBitmap: Sendable {
    let size: Int
    let png: Data
}

nonisolated enum FaviconImage {

    /// Vrai si les données sont réellement une image (rejette les pages HTML d'erreur, etc.)
    static func isValid(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
            return true
        }
        if let image = NSImage(data: data), image.size.width > 0 { return true }
        return false
    }

    /// Convertit une image quelconque (ico, gif, jpeg…) en PNG carré.
    static func squarePNG(from data: Data, pixelSize: Int) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    /// Les deux tailles que Vivaldi écrit lui-même : 16x16 et 32x32.
    static func bitmaps(from data: Data, sizes: [Int] = [16, 32]) -> [FaviconBitmap] {
        sizes.compactMap { size in
            squarePNG(from: data, pixelSize: size).map { FaviconBitmap(size: size, png: $0) }
        }
    }
}
