// Renders the disk image window background from the rain artwork, at 1x and 2x.
// Run via `./make-dmg.sh`.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let art = NSImage(contentsOfFile: args[1])
else { fatalError("usage: make-dmg-background <artwork> <output dir>") }

// Keep in sync with the window bounds and icon positions in make-dmg.sh.
let size = NSSize(width: 660, height: 400)
let green = NSColor(calibratedRed: 0.25, green: 1.0, blue: 0.4, alpha: 1)

func centered(_ text: String, font: NSFont, color: NSColor, y: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let s = NSAttributedString(string: text, attributes: attrs)
    s.draw(at: NSPoint(x: (size.width - s.size().width) / 2, y: y))
}

func render(scale: Int) -> NSBitmapImageRep {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                             pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Rain, cropped to the window's aspect ratio and dimmed so the icons and text stand out.
    let cropWidth = art.size.height * size.width / size.height
    let crop = NSRect(x: (art.size.width - cropWidth) / 2, y: 0, width: cropWidth, height: art.size.height)
    art.draw(in: NSRect(origin: .zero, size: size), from: crop, operation: .copy, fraction: 1)
    NSColor.black.withAlphaComponent(0.72).setFill()
    NSRect(origin: .zero, size: size).fill(using: .sourceOver)

    centered("MATRIX", font: .monospacedSystemFont(ofSize: 38, weight: .bold), color: green, y: 318, kern: 12)
    centered("DIGITAL RAIN SCREEN SAVER", font: .monospacedSystemFont(ofSize: 11, weight: .medium),
             color: green.withAlphaComponent(0.75), y: 298, kern: 3)
    centered("Double-click Matrix.saver to install", font: .systemFont(ofSize: 15, weight: .medium),
             color: .white, y: 54)
    centered("Blocked by macOS? See Instructions.txt", font: .systemFont(ofSize: 12),
             color: NSColor.white.withAlphaComponent(0.7), y: 32)
    return r
}

for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] {
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent(name)
    try! render(scale: scale).representation(using: .png, properties: [:])!.write(to: url)
    print("Wrote \(url.path)")
}
