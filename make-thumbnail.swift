// Renders thumbnail.png and thumbnail@2x.png (shown in System Settings) from a built
// Matrix.saver, using the default green settings. Run via `./build.sh --thumbnail`.
import AppKit
import ScreenSaver

let args = CommandLine.arguments
guard args.count == 3, let bundle = Bundle(path: args[1]), bundle.load(),
      let cls = bundle.principalClass as? ScreenSaverView.Type
else { fatalError("usage: make-thumbnail <Matrix.saver> <output dir>") }

// Ignore any options saved by earlier test runs in this process's defaults domain.
if let d = ScreenSaverDefaults(forModuleWithName: "local.agentsmith.MatrixSaver") {
    for key in ["colorIndex", "customHue", "speed", "density", "size", "charset", "customChars", "depth", "glow",
                "crt", "fps", "mainDisplayOnly", "introText", "messageText"] {
        d.removeObject(forKey: key)
    }
    // Plain rain only: none of the timed or text effects.
    for key in ["clock", "intro", "messages", "glitches"] { d.set(false, forKey: key) }
    d.synchronize()
}

let size = NSSize(width: 320, height: 200)
let view = cls.init(frame: NSRect(origin: .zero, size: size), isPreview: false)!

func rep(scale: Int) -> NSBitmapImageRep {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                             pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = size
    return r
}

// Let the rain fill the frame before capturing.
let scratch = rep(scale: 1)
view.cacheDisplay(in: view.bounds, to: scratch)
view.startAnimation()
for _ in 0..<150 {
    usleep(33_000)
    view.animateOneFrame()
    view.cacheDisplay(in: view.bounds, to: scratch)
}

for (scale, name) in [(1, "thumbnail.png"), (2, "thumbnail@2x.png")] {
    let r = rep(scale: scale)
    view.cacheDisplay(in: view.bounds, to: r)
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent(name)
    try! r.representation(using: .png, properties: [:])!.write(to: url)
    print("Wrote \(url.path)")
}
