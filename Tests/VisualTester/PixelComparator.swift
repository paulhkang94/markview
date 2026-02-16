import AppKit

struct ComparisonResult {
    let totalPixels: Int
    let differentPixels: Int
    let matchPercentage: Double

    var passed: Bool { matchPercentage >= threshold }
    let threshold: Double
}

struct PixelComparator {
    /// Per-channel tolerance (0-255) to account for anti-aliasing differences
    let tolerance: UInt8
    /// Minimum match percentage to pass (0.0 - 1.0)
    let threshold: Double

    init(tolerance: UInt8 = 2, threshold: Double = 0.995) {
        self.tolerance = tolerance
        self.threshold = threshold
    }

    /// Compare two PNG images and return the result
    func compare(actual: Data, golden: Data) -> ComparisonResult? {
        guard let actualBitmap = NSBitmapImageRep(data: actual),
              let goldenBitmap = NSBitmapImageRep(data: golden) else {
            return nil
        }

        let width = min(actualBitmap.pixelsWide, goldenBitmap.pixelsWide)
        let height = min(actualBitmap.pixelsHigh, goldenBitmap.pixelsHigh)
        let totalPixels = width * height
        var differentPixels = 0

        for y in 0..<height {
            for x in 0..<width {
                guard let actualColor = actualBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let goldenColor = goldenBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    differentPixels += 1
                    continue
                }

                let ar = UInt8(actualColor.redComponent * 255)
                let ag = UInt8(actualColor.greenComponent * 255)
                let ab = UInt8(actualColor.blueComponent * 255)
                let aa = UInt8(actualColor.alphaComponent * 255)

                let gr = UInt8(goldenColor.redComponent * 255)
                let gg = UInt8(goldenColor.greenComponent * 255)
                let gb = UInt8(goldenColor.blueComponent * 255)
                let ga = UInt8(goldenColor.alphaComponent * 255)

                if absDiff(ar, gr) > tolerance ||
                   absDiff(ag, gg) > tolerance ||
                   absDiff(ab, gb) > tolerance ||
                   absDiff(aa, ga) > tolerance {
                    differentPixels += 1
                }
            }
        }

        // Also count size difference as different pixels
        let sizeDiffPixels = abs(actualBitmap.pixelsWide * actualBitmap.pixelsHigh - goldenBitmap.pixelsWide * goldenBitmap.pixelsHigh)
        differentPixels += sizeDiffPixels

        let total = max(totalPixels + sizeDiffPixels, 1)
        let matchPct = Double(total - differentPixels) / Double(total)

        return ComparisonResult(
            totalPixels: total,
            differentPixels: differentPixels,
            matchPercentage: matchPct,
            threshold: threshold
        )
    }

    private func absDiff(_ a: UInt8, _ b: UInt8) -> UInt8 {
        a > b ? a - b : b - a
    }
}

// MARK: - WCAG Contrast Checking

struct ContrastChecker {
    /// Compute WCAG 2.1 relative luminance from sRGB color
    static func relativeLuminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        let r = linearize(c.redComponent)
        let g = linearize(c.greenComponent)
        let b = linearize(c.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Compute WCAG contrast ratio between two colors (returns value >= 1.0)
    static func contrastRatio(_ color1: NSColor, _ color2: NSColor) -> Double {
        let l1 = relativeLuminance(color1)
        let l2 = relativeLuminance(color2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG AA requires >= 4.5:1 for normal text, >= 3:1 for large text
    static func meetsAA(foreground: NSColor, background: NSColor, largeText: Bool = false) -> Bool {
        let ratio = contrastRatio(foreground, background)
        return ratio >= (largeText ? 3.0 : 4.5)
    }

    private static func linearize(_ value: CGFloat) -> Double {
        let v = Double(value)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}

/// Sample the dominant color in a rectangular region of a PNG image
func sampleColor(from pngData: Data, rect: NSRect) -> NSColor? {
    guard let bitmap = NSBitmapImageRep(data: pngData) else { return nil }

    var rTotal: CGFloat = 0, gTotal: CGFloat = 0, bTotal: CGFloat = 0
    var count: CGFloat = 0

    let minX = max(0, Int(rect.minX))
    let maxX = min(bitmap.pixelsWide, Int(rect.maxX))
    let minY = max(0, Int(rect.minY))
    let maxY = min(bitmap.pixelsHigh, Int(rect.maxY))

    for y in minY..<maxY {
        for x in minX..<maxX {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            rTotal += color.redComponent
            gTotal += color.greenComponent
            bTotal += color.blueComponent
            count += 1
        }
    }

    guard count > 0 else { return nil }
    return NSColor(srgbRed: rTotal / count, green: gTotal / count, blue: bTotal / count, alpha: 1.0)
}
