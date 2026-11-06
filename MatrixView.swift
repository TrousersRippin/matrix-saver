import AppKit
import CoreText
import ScreenSaver

/// User options, persisted with ScreenSaverDefaults so the preview and the real saver share them.
private struct Settings: Equatable {
    static let palette: [(name: String, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        ("Classic Green", 0.25, 1.0, 0.4),
        ("Cyan", 0.2, 0.9, 1.0),
        ("Blue", 0.3, 0.5, 1.0),
        ("Purple", 0.75, 0.4, 1.0),
        ("Red", 1.0, 0.25, 0.25),
        ("Amber", 1.0, 0.7, 0.15),
        ("White", 0.9, 0.9, 0.9),
    ]
    // Colour popup entries that follow the palette.
    static let customColorIndex = palette.count
    static let cycleColorIndex = palette.count + 1

    static let speedRange = 0.25...3.0
    static let densityRange = 0.2...3.0
    static let sizeRange = 0.5...3.0
    static let glowRange = 0.0...2.0
    static let frameRates = [15, 30, 60]

    static let charsets = ["Film", "Binary", "Latin", "Custom"]
    static let customCharset = 3

    static let presets: [(name: String, speed: Double, density: Double, size: Double, glow: Double)] = [
        ("Classic", 1.0, 1.0, 1.0, 1.0),
        ("Sparse", 0.8, 0.25, 1.2, 1.2),
        ("Downpour", 1.8, 1.79, 0.8, 0.8),
        ("Slow Drift", 0.35, 0.43, 1.4, 1.4),
    ]

    static let defaultIntro = "Wake up, {name}… / The Matrix has you…"
    static let defaultMessages = "WAKE UP / THERE IS NO SPOON / FOLLOW THE WHITE RABBIT / AGENT SMITH"

    // What 1.00× on the sliders means, relative to the original tuning.
    static let densityScale = 2.45
    static let sizeScale = 0.75

    var colorIndex = 0
    var customHue = 0.6
    var speed = 1.0     // multiplier on fall speed
    var density = 1.0   // multiplier on number of streams
    var size = 1.0      // multiplier on glyph size
    var charset = 0
    var customChars = ""

    var depth = true
    var glow = 1.0      // multiplier on glyph bloom
    var crt = false
    var glitches = true
    var fps = 30
    var mainDisplayOnly = false

    var clock = false
    var intro = true
    var introText = Settings.defaultIntro
    var messages = true
    var messageText = Settings.defaultMessages

    private static let store = ScreenSaverDefaults(forModuleWithName: "local.agentsmith.MatrixSaver")

    static func load() -> Settings {
        guard let d = store else { return Settings() }
        d.synchronize()  // pick up values saved by the Options sheet in another process
        let base = Settings()
        d.register(defaults: ["colorIndex": base.colorIndex, "customHue": base.customHue, "speed": base.speed,
                              "density": base.density, "size": base.size, "charset": base.charset,
                              "customChars": base.customChars, "depth": base.depth, "glow": base.glow,
                              "crt": base.crt, "glitches": base.glitches, "fps": base.fps,
                              "mainDisplayOnly": base.mainDisplayOnly, "clock": base.clock, "intro": base.intro,
                              "introText": base.introText, "messages": base.messages,
                              "messageText": base.messageText])
        var s = Settings()
        s.colorIndex = d.integer(forKey: "colorIndex").clamped(to: 0...cycleColorIndex)
        s.customHue = d.double(forKey: "customHue").clamped(to: 0...1)
        s.speed = d.double(forKey: "speed").clamped(to: speedRange)
        s.density = d.double(forKey: "density").clamped(to: densityRange)
        s.size = d.double(forKey: "size").clamped(to: sizeRange)
        s.charset = d.integer(forKey: "charset").clamped(to: 0...(charsets.count - 1))
        s.customChars = d.string(forKey: "customChars") ?? ""
        s.depth = d.bool(forKey: "depth")
        s.glow = d.double(forKey: "glow").clamped(to: glowRange)
        s.crt = d.bool(forKey: "crt")
        s.glitches = d.bool(forKey: "glitches")
        let fps = d.integer(forKey: "fps")
        s.fps = frameRates.contains(fps) ? fps : base.fps
        s.mainDisplayOnly = d.bool(forKey: "mainDisplayOnly")
        s.clock = d.bool(forKey: "clock")
        s.intro = d.bool(forKey: "intro")
        s.introText = d.string(forKey: "introText") ?? base.introText
        s.messages = d.bool(forKey: "messages")
        s.messageText = d.string(forKey: "messageText") ?? base.messageText
        return s
    }

    func save() {
        guard let d = Self.store else { return }
        d.set(colorIndex, forKey: "colorIndex")
        d.set(customHue, forKey: "customHue")
        d.set(speed, forKey: "speed")
        d.set(density, forKey: "density")
        d.set(size, forKey: "size")
        d.set(charset, forKey: "charset")
        d.set(customChars, forKey: "customChars")
        d.set(depth, forKey: "depth")
        d.set(glow, forKey: "glow")
        d.set(crt, forKey: "crt")
        d.set(glitches, forKey: "glitches")
        d.set(fps, forKey: "fps")
        d.set(mainDisplayOnly, forKey: "mainDisplayOnly")
        d.set(clock, forKey: "clock")
        d.set(intro, forKey: "intro")
        d.set(introText, forKey: "introText")
        d.set(messages, forKey: "messages")
        d.set(messageText, forKey: "messageText")
        d.synchronize()
    }

    /// The tint for the frame. `cycleHue` is only used in colour cycle mode.
    func tint(cycleHue: Double) -> CGColor {
        switch colorIndex {
        case Self.cycleColorIndex: return Self.color(hue: cycleHue)
        case Self.customColorIndex: return Self.color(hue: customHue)
        default:
            let c = Self.palette[colorIndex]
            return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
    }

    static func color(hue: Double) -> CGColor {
        NSColor(calibratedHue: CGFloat(hue), saturation: 0.75, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!.cgColor
    }


    /// The rain's characters, and whether they are mirrored as in the film. Latin and custom
    /// text stays readable. An empty custom set falls back to the film's characters.
    var glyphs: (strings: [String], mirrored: Bool) {
        switch charset {
        case 1: return (["0", "1"], false)
        case 2: return ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map(String.init), false)
        case Self.customCharset:
            var seen = Set<Character>()
            let unique = customChars.filter { !$0.isWhitespace && seen.insert($0).inserted }
            if !unique.isEmpty { return (unique.prefix(200).map(String.init), false) }
        default: break
        }
        var s = (0xFF66...0xFF9D).compactMap { UnicodeScalar($0).map { String($0) } }  // half-width katakana
        s += "0123456789Z:.=*+-<>¦|\"".map(String.init)
        return (s, true)
    }

    /// The Mac user's first name, for the {name} placeholder.
    static var userName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
    }

    /// Splits the intro or message text on "/" into its lines, filling in {name}.
    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "{name}", with: userName, options: .caseInsensitive)
            .split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

/// One plane of rain: a grid of cells with a fading brightness trail per column, and pre-rendered
/// white glyphs. Depth mode stacks three, drawn back to front.
private final class Layer {
    struct Drop {
        var col: Int
        var y: Float        // head position in rows (fractional)
        var speed: Float    // rows per second
        var lastRow: Int    // last row the head lit
    }

    let alpha: CGFloat
    let speedScale: Float
    var cellW: CGFloat = 0
    var cellH: CGFloat = 0
    var pad: CGFloat = 0
    var cols = 0
    var rows = 0

    var chars: [UInt16] = []      // glyph index per cell (row-major)
    var bright: [Float] = []      // 0...1 per cell
    var fade: [Float] = []        // brightness lost per second, per column
    var drops: [Drop] = []
    var randomGlyphs: UInt16 = 1  // glyphs the rain may pick; message letters follow these

    var trailGlyphs: [CGImage] = []  // white, soft glow; tinted with the frame
    var headGlyphs: [CGImage] = []   // white, full glow; tinted with the frame
    var coreGlyphs: [CGImage] = []   // white, no glow; drawn after tinting so heads stay near-white

    init(alpha: CGFloat, speedScale: Float) {
        self.alpha = alpha
        self.speedScale = speedScale
    }

    // Fade scales with speed so trail length stays the same at any speed.
    func randomFade(speed: Float) -> Float {
        Float.random(in: 0.35...0.85) * speed * speedScale
    }

    func newDrop(speed: Float) -> Drop {
        let y = -Float.random(in: 0...Float(rows) * 0.6)
        let d = Drop(col: Int.random(in: 0..<cols), y: y,
                     speed: Float.random(in: 9...26) * speed * speedScale, lastRow: Int(floor(y)))
        return d
    }

    func step(_ dt: Float, speed: Float) {
        for r in 0..<rows {
            let base = r * cols
            for c in 0..<cols where bright[base + c] > 0 {
                bright[base + c] = max(0, bright[base + c] - fade[c] * dt)
            }
        }

        for i in drops.indices {
            drops[i].y += drops[i].speed * dt
            let row = Int(floor(drops[i].y))
            while drops[i].lastRow < row {
                drops[i].lastRow += 1
                let r = drops[i].lastRow
                guard r >= 0 && r < rows else { continue }
                let idx = r * cols + drops[i].col
                chars[idx] = UInt16.random(in: 0..<randomGlyphs)
                bright[idx] = 1
            }
            if drops[i].lastRow >= rows + 4 {
                drops[i] = newDrop(speed: speed)
                fade[drops[i].col] = randomFade(speed: speed)
            }
        }

        // Occasional glyph mutation within trails.
        let mutations = max(1, Int(Float(cols * rows) * 0.25 * dt))
        for _ in 0..<mutations {
            chars[Int.random(in: 0..<chars.count)] = UInt16.random(in: 0..<randomGlyphs)
        }
    }
}

/// Digital-rain screensaver. Glyphs are pre-rendered in white into small images, so a frame is
/// just blits followed by one multiply fill that tints everything; that lets the colour change
/// every frame without re-rendering any glyphs.
/// The Objective-C name is deliberately distinctive: every saver shown in System Settings is
/// loaded into one legacyScreenSaver process, and a clash with another saver's "MatrixView"
/// class means the wrong one gets used.
@objc(AgentSmithMatrixView)
final class MatrixView: ScreenSaverView {
    private struct Message {
        var col: Int
        var row: Int
        var letters: [UInt16]
        var age: Float = 0
        var shown: Int { min(letters.count, Int(age * 12)) }
    }

    private struct GlitchBand {
        var y0: CGFloat
        var y1: CGFloat
        var dx: CGFloat
    }

    private var settings = Settings.load()
    private var layers: [Layer] = []
    private var laidOutSize: CGSize = .zero
    private var lastTime: CFTimeInterval = 0
    private var cycleHue = 0.37
    private var crtImage: CGImage?

    private var introLines: [String] = []
    private var introActive = false
    private var introTime = 0.0

    private var clockMinute = -1
    private var clockMask: [Bool] = []
    private var clockBox: (c0: Int, c1: Int, r0: Int, r1: Int)?

    private var messageLetters: [[UInt16]] = []
    private var message: Message?
    private var nextMessage: Float = 0

    private var nextGlitch: Float = 0
    private var glitchLeft: Float = 0
    private var glitchStutter = false
    private var glitchBands: [GlitchBand] = []
    private var glitchPatch: (c0: Int, c1: Int, r0: Int, r1: Int) = (0, 0, 0, 0)

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / Double(settings.fps)
        NotificationCenter.default.addObserver(self, selector: #selector(optionsDidChange),
                                               name: .matrixOptionsChanged, object: nil)
        if !isPreview {
            // legacyScreenSaver on recent macOS often never calls stopAnimation and keeps
            // instances alive after the saver is dismissed; go idle ourselves instead.
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(screenSaverWillStop),
                name: NSNotification.Name("com.apple.screensaver.willstop"), object: nil)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Stops animating and frees the grid and glyph images. Deliberately not exit(0): the host
    /// process is shared with System Settings' previews, and killing it leaves later Options
    /// sheets unresponsive.
    @objc private func screenSaverWillStop() {
        if isAnimating { stopAnimation() }
        layers = []
        crtImage = nil
        clockMask = []
        clockBox = nil
        messageLetters = []
        message = nil
        glitchBands = []
        laidOutSize = .zero  // lay out afresh if this instance is ever drawn again
    }

    /// True on a secondary display when the saver is set to the main display only. The primary
    /// display's origin is always zero. With no screen to go on, the saver draws as normal.
    private var isBlanked: Bool {
        guard settings.mainDisplayOnly, !isPreview, let screen = window?.screen else { return false }
        return screen.frame.origin != .zero
    }

    // MARK: - Layout

    private func layout(for size: CGSize) {
        laidOutSize = size
        let baseSize = isPreview ? 7 : max(14, size.height / 55)
        let fontSize = max(5, (baseSize * CGFloat(settings.size * Settings.sizeScale)).rounded())
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        // Back to front: font scale, brightness, speed, share of the streams.
        let planes: [(font: CGFloat, alpha: CGFloat, speed: Float, share: Double)] = settings.depth
            ? [(0.6, 0.35, 0.55, 0.2), (0.8, 0.6, 0.78, 0.3), (1, 1, 1, 0.45)]
            : [(1, 1, 1, 1)]

        let (strings, mirrored) = settings.glyphs

        // Message letters are added to the front layer only, unmirrored so they can be read.
        let messages = settings.messages ? Settings.lines(settings.messageText).map { Array($0.uppercased().prefix(60)) } : []
        var seen = Set<Character>()
        let letters = messages.flatMap { $0 }.filter { seen.insert($0).inserted }
        var letterIndex: [Character: UInt16] = [:]
        for (i, ch) in letters.enumerated() { letterIndex[ch] = UInt16(strings.count + i) }
        messageLetters = messages.map { $0.compactMap { letterIndex[$0] } }

        let speed = Float(settings.speed)
        layers = planes.enumerated().map { i, plane in
            let layer = Layer(alpha: plane.alpha, speedScale: plane.speed)
            let font = max(3, (fontSize * plane.font).rounded())
            layer.cellW = (font * 0.72).rounded()
            layer.cellH = (font * 1.08).rounded()
            layer.pad = (font * 0.5 * max(1, CGFloat(settings.glow))).rounded()
            layer.cols = max(1, Int(ceil(size.width / layer.cellW)))
            layer.rows = max(1, Int(ceil(size.height / layer.cellH)))
            layer.randomGlyphs = UInt16(strings.count)

            layer.chars = (0..<(layer.cols * layer.rows)).map { _ in UInt16.random(in: 0..<layer.randomGlyphs) }
            layer.bright = Array(repeating: 0, count: layer.cols * layer.rows)
            layer.fade = (0..<layer.cols).map { _ in layer.randomFade(speed: speed) }
            let dropCount = Double(layer.cols) * 0.9 * settings.density * Settings.densityScale * plane.share
            layer.drops = (0..<max(1, Int(dropCount))).map { _ in
                var d = layer.newDrop(speed: speed)
                d.y = -Float.random(in: 0...Float(layer.rows))
                d.lastRow = Int(floor(d.y))
                return d
            }

            let isFront = i == planes.count - 1
            let entries = strings.map { ($0, mirrored) } + (isFront ? letters.map { (String($0), false) } : [])
            let white = CGColor(gray: 1, alpha: 1)
            layer.trailGlyphs = renderGlyphs(entries, layer: layer, fontSize: font, scale: scale,
                                             glow: CGColor(gray: 0.8, alpha: 0.7))
            layer.headGlyphs = renderGlyphs(entries, layer: layer, fontSize: font, scale: scale, glow: white)
            layer.coreGlyphs = renderGlyphs(entries, layer: layer, fontSize: font, scale: scale, glow: nil)
            return layer
        }

        // These all hold positions in the old grid.
        message = nil
        glitchLeft = 0
        glitchBands = []
        clockMinute = -1
        clockMask = []
        clockBox = nil
        crtImage = settings.crt ? renderCRT(size: size, scale: scale) : nil
    }

    private func renderGlyphs(_ entries: [(String, Bool)], layer: Layer, fontSize: CGFloat, scale: CGFloat,
                              glow: CGColor?, color: CGColor = CGColor(gray: 1, alpha: 1)) -> [CGImage] {
        let font = CTFontCreateWithName("HiraginoSans-W4" as CFString, fontSize, nil)
        let imgW = layer.cellW + layer.pad * 2
        let imgH = layer.cellH + layer.pad * 2
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let blur = fontSize * 0.45 * CGFloat(settings.glow)

        return entries.compactMap { str, mirrored in
            guard let ctx = CGContext(data: nil, width: Int(imgW * scale), height: Int(imgH * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            if mirrored {  // as in the film
                ctx.translateBy(x: imgW, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            if let glow, blur > 0 { ctx.setShadow(offset: .zero, blur: blur, color: glow) }

            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
            let line = CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, str as CFString, attrs as CFDictionary))
            let gb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: layer.pad + (layer.cellW - gb.width) / 2 - gb.minX,
                                       y: layer.pad + layer.cellH * 0.18)
            CTLineDraw(line, ctx)
            return ctx.makeImage()
        }
    }

    /// Scanlines and darkened edges, drawn over each finished frame.
    private func renderCRT(size: CGSize, scale: CGFloat) -> CGImage? {
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: info) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.3))
        for y in stride(from: CGFloat(0), to: size.height, by: 3) {
            ctx.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
        }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.65)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                                     colors: colors, locations: [0.55, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: hypot(size.width, size.height) / 2, options: [])
        }
        return ctx.makeImage()
    }

    // MARK: - Animation

    override func startAnimation() {
        // legacyScreenSaver may reuse an instance created before the options were changed
        // (possibly in another process), so pick up the latest saved options each time.
        let latest = Settings.load()
        if latest != settings {
            settings = latest
            laidOutSize = .zero
        }
        animationTimeInterval = 1.0 / Double(settings.fps)
        super.startAnimation()
        lastTime = CACurrentMediaTime()

        introLines = Settings.lines(settings.introText)
        introTime = 0
        introActive = !isPreview && settings.intro && !introLines.isEmpty
        message = nil
        nextMessage = Float.random(in: 5...15)
        glitchLeft = 0
        glitchBands = []
        nextGlitch = Float.random(in: 10...30)
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, max(0, now - lastTime)))
        lastTime = now
        step(dt)
        setNeedsDisplay(bounds)
    }

    private func step(_ dt: Float) {
        guard let front = layers.last, dt > 0 else { return }
        cycleHue = (cycleHue + Double(dt) / 120).truncatingRemainder(dividingBy: 1)

        if introActive {
            introTime += Double(dt)
            if introFrame() == nil { introActive = false }
            return
        }

        if settings.clock { updateClock(front) }
        if !stepGlitch(dt, front) {
            let speed = Float(settings.speed)
            for layer in layers { layer.step(dt, speed: speed) }
        }
        stepMessage(dt, front)
    }

    // MARK: - Film intro

    /// What the intro shows at the current time: a line and how many of its characters are typed
    /// so far. Nil once the intro has finished.
    private func introFrame() -> (line: String, shown: Int)? {
        let typeRate = 16.0, hold = 1.4, gap = 0.25
        var t = introTime - 0.8  // a moment of black first
        if t < 0 { return ("", 0) }
        for line in introLines {
            let total = Double(line.count) / typeRate + hold
            if t < total { return (line, min(line.count, Int(t * typeRate))) }
            t -= total
            if t < gap { return ("", 0) }
            t -= gap
        }
        return nil
    }

    private func drawIntro(_ ctx: CGContext) {
        guard let frame = introFrame() else { return }
        let fontSize = max(12, bounds.height / 26)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                      kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, String(frame.line.prefix(frame.shown)) as CFString, attrs as CFDictionary))
        let origin = CGPoint(x: bounds.width * 0.06, y: bounds.height * 0.8)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: fontSize * 0.4, color: CGColor(gray: 1, alpha: 0.8))
        ctx.textMatrix = .identity
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
        if Int(introTime * 2.5) % 2 == 0 {
            let x = origin.x + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + fontSize * 0.1
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: x, y: origin.y - fontSize * 0.2, width: fontSize * 0.6, height: fontSize * 1.1))
        }
        ctx.restoreGState()
    }

    // MARK: - Rain clock

    private func updateClock(_ front: Layer) {
        let minute = Int(Date().timeIntervalSince1970) / 60
        guard minute != clockMinute else { return }
        clockMinute = minute
        buildClockMask(front)
    }

    /// Rasterises the time at one pixel per cell, marking which of the front layer's cells form it.
    private func buildClockMask(_ front: Layer) {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let time = formatter.string(from: Date()).filter { $0.isNumber || $0 == ":" || $0 == "." }

        guard let ctx = CGContext(data: nil, width: front.cols, height: front.rows, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return }
        ctx.scaleBy(x: 1 / front.cellW, y: 1 / front.cellH)

        func line(size: CGFloat) -> CTLine {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy)
            let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                          kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)]
            return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, time as CFString, attrs as CFDictionary))
        }
        let measured = CTLineGetBoundsWithOptions(line(size: 100), .useGlyphPathBounds)
        guard measured.width > 0, measured.height > 0 else { return }
        let fit = min(bounds.width * 0.55 / measured.width, bounds.height * 0.4 / measured.height) * 100
        let clockLine = line(size: fit)
        let b = CTLineGetBoundsWithOptions(clockLine, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (bounds.width - b.width) / 2 - b.minX, y: (bounds.height - b.height) / 2 - b.minY)
        CTLineDraw(clockLine, ctx)

        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return }
        var mask = Array(repeating: false, count: front.cols * front.rows)
        var c0 = front.cols, c1 = -1, r0 = front.rows, r1 = -1
        for r in 0..<front.rows {
            for c in 0..<front.cols where data[r * ctx.bytesPerRow + c] > 128 {
                mask[r * front.cols + c] = true
                c0 = min(c0, c); c1 = max(c1, c); r0 = min(r0, r); r1 = max(r1, r)
            }
        }
        clockMask = mask
        clockBox = c1 < 0 ? nil : (max(0, c0 - 2), min(front.cols - 1, c1 + 2), max(0, r0 - 2), min(front.rows - 1, r1 + 2))
    }

    // MARK: - Hidden messages

    private func stepMessage(_ dt: Float, _ front: Layer) {
        if var m = message {
            m.age += dt
            let hold: Float = 2.5
            if m.age > Float(m.letters.count) / 12 + hold {
                message = nil  // stop holding the cells; they fade like any other trail
                nextMessage = Float.random(in: 15...40)
                return
            }
            for i in 0..<m.shown {
                let idx = (m.row + i) * front.cols + m.col
                front.chars[idx] = m.letters[i]
                front.bright[idx] = 1
            }
            message = m
            return
        }
        nextMessage -= dt
        if nextMessage <= 0 {
            startMessage(front)
            nextMessage = Float.random(in: 15...40)
        }
    }

    private func startMessage(_ front: Layer) {
        guard let letters = messageLetters.filter({ !$0.isEmpty && $0.count <= front.rows }).randomElement() else { return }
        message = Message(col: Int.random(in: 0..<front.cols), row: Int.random(in: 0...(front.rows - letters.count)),
                          letters: letters)
    }

    // MARK: - Glitches

    /// Advances any glitch, and returns true while the rain should freeze.
    private func stepGlitch(_ dt: Float, _ front: Layer) -> Bool {
        guard settings.glitches else { return false }
        if glitchLeft > 0 {
            glitchLeft -= dt
            if glitchLeft <= 0 {
                glitchBands = []
                nextGlitch = Float.random(in: 20...60)
                return false
            }
            if glitchStutter {
                makeGlitchBands()
                return true
            }
            let p = glitchPatch
            for r in p.r0...p.r1 {
                for c in p.c0...p.c1 {
                    let idx = r * front.cols + c
                    front.bright[idx] = Float.random(in: 0.2...1)
                    front.chars[idx] = UInt16.random(in: 0..<front.randomGlyphs)
                }
            }
            return false
        }
        nextGlitch -= dt
        if nextGlitch <= 0 { startGlitch(stutter: Bool.random(), front) }
        return false
    }

    private func startGlitch(stutter: Bool, _ front: Layer) {
        glitchStutter = stutter
        if stutter {
            glitchLeft = Float.random(in: 0.12...0.35)
            makeGlitchBands()
        } else {
            glitchLeft = Float.random(in: 0.25...0.6)
            let w = max(1, Int(Double(front.cols) * Double.random(in: 0.1...0.3)))
            let h = max(1, Int(Double(front.rows) * Double.random(in: 0.1...0.25)))
            let c0 = Int.random(in: 0...(front.cols - w)), r0 = Int.random(in: 0...(front.rows - h))
            glitchPatch = (c0, c0 + w - 1, r0, r0 + h - 1)
        }
    }

    private func makeGlitchBands() {
        glitchBands = (0..<Int.random(in: 2...5)).map { _ in
            let y0 = CGFloat.random(in: 0...bounds.height)
            let limit = bounds.width * 0.08
            return GlitchBand(y0: y0, y1: y0 + bounds.height * CGFloat.random(in: 0.02...0.12),
                              dx: CGFloat.random(in: -limit...limit))
        }
    }

    private func glitchShift(atY y: CGFloat) -> CGFloat {
        for band in glitchBands where y >= band.y0 && y < band.y1 { return band.dx }
        return 0
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(bounds)
        if isBlanked { return }

        if bounds.size != laidOutSize { layout(for: bounds.size) }
        guard let front = layers.last, !front.trailGlyphs.isEmpty else { return }

        if introActive {
            drawIntro(ctx)
        } else {
            for layer in layers { drawLayer(layer, ctx, isFront: layer === front) }
        }

        // Everything so far is white: tint the whole frame in one go.
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(settings.tint(cycleHue: cycleHue))
        ctx.fill(bounds)
        ctx.setBlendMode(.normal)

        if !introActive {
            for layer in layers { drawCores(layer, ctx, isFront: layer === front) }
            if let m = message { drawMessage(m, front, ctx) }
        }

        if let crtImage {
            ctx.setAlpha(1)
            ctx.draw(crtImage, in: bounds)
        }
    }

    private func drawLayer(_ layer: Layer, _ ctx: CGContext, isFront: Bool) {
        let imgW = layer.cellW + layer.pad * 2
        let imgH = layer.cellH + layer.pad * 2
        let top = bounds.height
        let box = settings.clock && isFront ? clockBox : nil

        // Darken the rain behind the clock so the digits stand out.
        if let box {
            ctx.setAlpha(1)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.75))
            ctx.fill(CGRect(x: CGFloat(box.c0) * layer.cellW, y: top - CGFloat(box.r1 + 1) * layer.cellH,
                            width: CGFloat(box.c1 - box.c0 + 1) * layer.cellW,
                            height: CGFloat(box.r1 - box.r0 + 1) * layer.cellH))
        }

        for r in 0..<layer.rows {
            let y = top - CGFloat(r + 1) * layer.cellH - layer.pad
            let dx = glitchBands.isEmpty ? 0 : glitchShift(atY: y)
            let base = r * layer.cols
            for c in 0..<layer.cols {
                var b = layer.bright[base + c]
                if let box, r >= box.r0, r <= box.r1, c >= box.c0, c <= box.c1 {
                    b = clockMask[base + c] ? max(b, 0.95) : b * 0.3
                }
                if b < 0.02 { continue }
                ctx.setAlpha(CGFloat(b * b) * layer.alpha)
                ctx.draw(layer.trailGlyphs[Int(layer.chars[base + c])],
                         in: CGRect(x: CGFloat(c) * layer.cellW - layer.pad + dx, y: y, width: imgW, height: imgH))
            }
        }

        ctx.setAlpha(layer.alpha)
        forEachVisibleHead(layer, box: box) { idx, x, y in
            ctx.draw(layer.headGlyphs[idx], in: CGRect(x: x, y: y, width: imgW, height: imgH))
        }
    }

    private func drawCores(_ layer: Layer, _ ctx: CGContext, isFront: Bool) {
        let imgW = layer.cellW + layer.pad * 2
        let imgH = layer.cellH + layer.pad * 2
        ctx.setAlpha(0.85 * layer.alpha)
        forEachVisibleHead(layer, box: settings.clock && isFront ? clockBox : nil) { idx, x, y in
            ctx.draw(layer.coreGlyphs[idx], in: CGRect(x: x, y: y, width: imgW, height: imgH))
        }

        // Lift the clock's digits above the rain around them.
        guard settings.clock, isFront, let box = clockBox else { return }
        ctx.setAlpha(0.4)
        for r in box.r0...box.r1 {
            let y = bounds.height - CGFloat(r + 1) * layer.cellH - layer.pad
            let dx = glitchBands.isEmpty ? 0 : glitchShift(atY: y)
            for c in box.c0...box.c1 where clockMask[r * layer.cols + c] {
                ctx.draw(layer.coreGlyphs[Int(layer.chars[r * layer.cols + c])],
                         in: CGRect(x: CGFloat(c) * layer.cellW - layer.pad + dx, y: y, width: imgW, height: imgH))
            }
        }
    }

    private func forEachVisibleHead(_ layer: Layer, box: (c0: Int, c1: Int, r0: Int, r1: Int)?,
                                    _ body: (Int, CGFloat, CGFloat) -> Void) {
        for d in layer.drops where d.lastRow >= 0 && d.lastRow < layer.rows {
            if let box, d.lastRow >= box.r0, d.lastRow <= box.r1, d.col >= box.c0, d.col <= box.c1 { continue }
            let y = bounds.height - CGFloat(d.lastRow + 1) * layer.cellH - layer.pad
            let dx = glitchBands.isEmpty ? 0 : glitchShift(atY: y)
            body(Int(layer.chars[d.lastRow * layer.cols + d.col]), CGFloat(d.col) * layer.cellW - layer.pad + dx, y)
        }
    }

    private func drawMessage(_ m: Message, _ front: Layer, _ ctx: CGContext) {
        let imgW = front.cellW + front.pad * 2
        let imgH = front.cellH + front.pad * 2
        ctx.setAlpha(0.8)
        for i in 0..<m.shown {
            let y = bounds.height - CGFloat(m.row + i + 1) * front.cellH - front.pad
            ctx.draw(front.coreGlyphs[Int(m.letters[i])],
                     in: CGRect(x: CGFloat(m.col) * front.cellW - front.pad, y: y, width: imgW, height: imgH))
        }
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { OptionsController.present() }

    @objc private func optionsDidChange() {
        settings = Settings.load()
        animationTimeInterval = 1.0 / Double(settings.fps)
        laidOutSize = .zero  // force re-layout with the new options
        setNeedsDisplay(bounds)
    }

    #if MATRIX_TEST
    // Lets the render tests fire the randomly timed effects on demand.
    @objc func testStartGlitch(_ stutter: NSNumber) {
        if let front = layers.last { startGlitch(stutter: stutter.boolValue, front) }
    }
    @objc func testStartMessage() {
        if let front = layers.last { startMessage(front) }
    }
    #endif
}

private extension Notification.Name {
    static let matrixOptionsChanged = Notification.Name("local.agentsmith.MatrixSaver.optionsChanged")
}

/// Owns the Options sheet, independently of any MatrixView. System Settings often discards the
/// view that supplied the sheet while the sheet is still open; controls only hold their target
/// weakly, so if the view were the target the buttons would silently stop working.
private final class OptionsController: NSObject {
    /// Keeps the controller alive while its sheet is up.
    private static var current: OptionsController?

    static func present() -> NSWindow {
        current?.close()  // a sheet the host lost track of; start afresh
        let c = OptionsController()
        current = c
        return c.window
    }

    private var window: NSWindow!
    private var pages: [NSView] = []

    private var presetPopup: NSPopUpButton!
    private var colorPopup: NSPopUpButton!
    private var hueSlider: NSSlider!
    private var speedSlider: NSSlider!
    private var densitySlider: NSSlider!
    private var sizeSlider: NSSlider!
    private var speedLabel: NSTextField!
    private var densityLabel: NSTextField!
    private var sizeLabel: NSTextField!
    private var charsetPopup: NSPopUpButton!
    private var customCharsField: NSTextField!

    private var depthCheck: NSButton!
    private var glowSlider: NSSlider!
    private var glowLabel: NSTextField!
    private var crtCheck: NSButton!
    private var glitchCheck: NSButton!
    private var fpsPopup: NSPopUpButton!
    private var displayPopup: NSPopUpButton!

    private var clockCheck: NSButton!
    private var introCheck: NSButton!
    private var introField: NSTextField!
    private var messagesCheck: NSButton!
    private var messagesField: NSTextField!

    private override init() {
        super.init()
        window = makeSheet()
        show(Settings.load())
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    /// Lays the sheet out with fixed frames rather than Auto Layout: inside legacyScreenSaver an
    /// unsatisfiable constraint is raised as an uncaught exception, which leaves the sheet unresponsive.
    private func makeSheet() -> NSWindow {
        let margin: CGFloat = 20, rowH: CGFloat = 32, gap: CGFloat = 8
        let labelW: CGFloat = 76, controlW: CGFloat = 200, valueW: CGFloat = 56
        let controlX = margin + labelW + gap
        let valueX = controlX + controlW + gap
        let width = valueX + valueW + margin
        let content = FlippedView()

        // Where `place` currently puts controls: a page, or the sheet itself offset by the margin.
        var parent: NSView = content
        var originY = margin

        // Sizes a control to fit, then centres it vertically in row `row` at x.
        func place(_ v: NSControl, row: CGFloat, x: CGFloat, width w: CGFloat? = nil) {
            v.sizeToFit()
            let h = v.frame.height
            v.frame = NSRect(x: x, y: originY + row * rowH + (rowH - h) / 2, width: w ?? v.frame.width, height: h)
            parent.addSubview(v)
        }
        @discardableResult func label(_ text: String, row: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            place(l, row: row, x: margin, width: labelW)
            return l
        }
        func slider(_ range: ClosedRange<Double>, row: CGFloat) -> NSSlider {
            let s = NSSlider(value: 1, minValue: range.lowerBound, maxValue: range.upperBound,
                             target: self, action: #selector(controlsChanged))
            s.isContinuous = true
            place(s, row: row, x: controlX, width: controlW)
            return s
        }
        func valueLabel(row: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: "0.00×")
            l.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            place(l, row: row, x: valueX, width: valueW)
            return l
        }
        func popup(_ titles: [String], row: CGFloat, action: Selector = #selector(controlsChanged)) -> NSPopUpButton {
            let p = NSPopUpButton()
            p.addItems(withTitles: titles)
            p.target = self
            p.action = action
            place(p, row: row, x: controlX - 3, width: controlW * 0.75)
            return p
        }
        func checkbox(_ title: String, row: CGFloat, x: CGFloat) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(controlsChanged))
            place(b, row: row, x: x)
            return b
        }
        func textField(row: CGFloat, x: CGFloat, width w: CGFloat) -> NSTextField {
            let f = NSTextField(string: "")
            f.usesSingleLineMode = true
            f.cell?.isScrollable = true
            f.cell?.wraps = false
            place(f, row: row, x: x, width: w)
            return f
        }
        func newPage() {
            let page = FlippedView(frame: NSRect(x: 0, y: margin + rowH * 1.25, width: width, height: rowH * 8))
            content.addSubview(page)
            pages.append(page)
            parent = page
            originY = 0
        }

        let tabs = NSSegmentedControl(labels: ["Rain", "Effects", "Text"], trackingMode: .selectOne,
                                      target: self, action: #selector(pageChanged(_:)))
        tabs.selectedSegment = 0
        tabs.sizeToFit()
        place(tabs, row: 0, x: (width - tabs.frame.width) / 2)

        // Rain page.
        newPage()
        label("Preset:", row: 0)
        presetPopup = popup(["Custom"] + Settings.presets.map(\.name), row: 0, action: #selector(presetChosen))
        presetPopup.autoenablesItems = false
        presetPopup.item(at: 0)?.isEnabled = false

        label("Colour:", row: 1)
        colorPopup = popup(Settings.palette.map(\.name) + ["Custom", "Colour Cycle"], row: 1)
        for (item, c) in zip(colorPopup.itemArray, Settings.palette) {
            item.image = swatch(NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
        }
        colorPopup.item(at: Settings.cycleColorIndex)?.image = cycleSwatch()

        label("Hue:", row: 2)
        hueSlider = slider(0...1, row: 2)

        label("Speed:", row: 3)
        speedSlider = slider(Settings.speedRange, row: 3)
        speedLabel = valueLabel(row: 3)
        label("Density:", row: 4)
        densitySlider = slider(Settings.densityRange, row: 4)
        densityLabel = valueLabel(row: 4)
        label("Font size:", row: 5)
        sizeSlider = slider(Settings.sizeRange, row: 5)
        sizeLabel = valueLabel(row: 5)

        label("Characters:", row: 6)
        charsetPopup = popup(Settings.charsets, row: 6)
        label("Custom:", row: 7)
        customCharsField = textField(row: 7, x: controlX, width: controlW)
        customCharsField.placeholderString = "Your own characters"

        // Effects page.
        newPage()
        depthCheck = checkbox("Depth (layers of rain)", row: 0, x: controlX)
        label("Glow:", row: 1)
        glowSlider = slider(Settings.glowRange, row: 1)
        glowLabel = valueLabel(row: 1)
        crtCheck = checkbox("CRT scanlines and dark edges", row: 2, x: controlX)
        glitchCheck = checkbox("Glitches", row: 3, x: controlX)
        label("Frame rate:", row: 4)
        fpsPopup = popup(["15 fps (saves power)", "30 fps", "60 fps"], row: 4)
        label("Displays:", row: 5)
        displayPopup = popup(["Every display", "Main display only"], row: 5)

        // Text page.
        newPage()
        let fieldW = width - margin * 2
        clockCheck = checkbox("Rain clock", row: 0, x: margin)
        introCheck = checkbox("Film intro, typed on black before the rain", row: 1, x: margin)
        introField = textField(row: 2, x: margin, width: fieldW)
        messagesCheck = checkbox("Hidden messages in the rain", row: 3, x: margin)
        messagesField = textField(row: 4, x: margin, width: fieldW)

        for page in pages.dropFirst() { page.isHidden = true }
        parent = content
        originY = margin

        // Credit line. Bundle.main is the host process here, so look up the saver's own bundle.
        let creditRow: CGFloat = 9.35
        let version = Bundle(for: OptionsController.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let credit = NSTextField(labelWithString: "Version \(version) · Agent Smith")
        credit.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        credit.textColor = .secondaryLabelColor
        credit.alignment = .center
        place(credit, row: creditRow, x: margin, width: width - margin * 2)

        // Button row: Defaults on the left, Cancel and OK on the right.
        let buttonRow = creditRow + 1
        let reset = NSButton(title: "Defaults", target: self, action: #selector(resetDefaults))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSheet))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(saveSheet))
        ok.keyEquivalent = "\r"
        for b in [reset, cancel, ok] { b.sizeToFit() }
        let buttonW = max(80, cancel.frame.width, ok.frame.width)
        place(ok, row: buttonRow, x: width - margin - buttonW, width: buttonW)
        place(cancel, row: buttonRow, x: width - margin - buttonW * 2 - 12, width: buttonW)
        place(reset, row: buttonRow, x: margin)

        let height = margin + (buttonRow + 1) * rowH + margin / 2
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled], backing: .buffered, defer: true)
        // NSWindow defaults to releasing itself on close, an over-release under ARC that can
        // crash the host and leave the Options button dead until it is relaunched.
        w.isReleasedWhenClosed = false
        w.title = "Matrix Options"
        w.contentView = content
        return w
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            color.setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).fill()
            return true
        }
    }

    private func cycleSwatch() -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            NSGradient(colors: [.systemRed, .systemGreen, .systemBlue])?.draw(in: path, angle: 90)
            return true
        }
    }

    private func show(_ s: Settings) {
        colorPopup.selectItem(at: s.colorIndex)
        hueSlider.doubleValue = s.customHue
        speedSlider.doubleValue = s.speed
        densitySlider.doubleValue = s.density
        sizeSlider.doubleValue = s.size
        charsetPopup.selectItem(at: s.charset)
        customCharsField.stringValue = s.customChars

        depthCheck.state = s.depth ? .on : .off
        glowSlider.doubleValue = s.glow
        crtCheck.state = s.crt ? .on : .off
        glitchCheck.state = s.glitches ? .on : .off
        fpsPopup.selectItem(at: Settings.frameRates.firstIndex(of: s.fps) ?? 1)
        displayPopup.selectItem(at: s.mainDisplayOnly ? 1 : 0)

        clockCheck.state = s.clock ? .on : .off
        introCheck.state = s.intro ? .on : .off
        introField.stringValue = s.introText
        messagesCheck.state = s.messages ? .on : .off
        messagesField.stringValue = s.messageText
        controlsChanged()
    }

    @objc private func pageChanged(_ sender: NSSegmentedControl) {
        for (i, page) in pages.enumerated() { page.isHidden = i != sender.selectedSegment }
    }

    @objc private func controlsChanged() {
        speedLabel.stringValue = String(format: "%.2f×", speedSlider.doubleValue)
        densityLabel.stringValue = String(format: "%.2f×", densitySlider.doubleValue)
        sizeLabel.stringValue = String(format: "%.2f×", sizeSlider.doubleValue)
        glowLabel.stringValue = String(format: "%.2f×", glowSlider.doubleValue)

        hueSlider.isEnabled = colorPopup.indexOfSelectedItem == Settings.customColorIndex
        colorPopup.item(at: Settings.customColorIndex)?.image =
            swatch(NSColor(cgColor: Settings.color(hue: hueSlider.doubleValue)) ?? .white)
        let charset = charsetPopup.indexOfSelectedItem
        customCharsField.isEnabled = charset == Settings.customCharset
        introField.isEnabled = introCheck.state == .on
        messagesField.isEnabled = messagesCheck.state == .on
        // Show the preset these values match, or Custom when they match none.
        let close: (Double, Double) -> Bool = { abs($0 - $1) < 0.005 }
        let match = Settings.presets.firstIndex {
            close($0.speed, speedSlider.doubleValue) && close($0.density, densitySlider.doubleValue)
                && close($0.size, sizeSlider.doubleValue) && close($0.glow, glowSlider.doubleValue)
        }
        presetPopup.selectItem(at: match.map { $0 + 1 } ?? 0)
    }

    @objc private func presetChosen() {
        let i = presetPopup.indexOfSelectedItem - 1
        guard Settings.presets.indices.contains(i) else { return }
        let p = Settings.presets[i]
        speedSlider.doubleValue = p.speed
        densitySlider.doubleValue = p.density
        sizeSlider.doubleValue = p.size
        glowSlider.doubleValue = p.glow
        controlsChanged()
    }

    @objc private func resetDefaults() {
        show(Settings())
    }

    @objc private func saveSheet() {
        var s = Settings()
        s.colorIndex = colorPopup.indexOfSelectedItem
        s.customHue = hueSlider.doubleValue
        s.speed = speedSlider.doubleValue
        s.density = densitySlider.doubleValue
        s.size = sizeSlider.doubleValue
        s.charset = charsetPopup.indexOfSelectedItem
        s.customChars = customCharsField.stringValue
        s.depth = depthCheck.state == .on
        s.glow = glowSlider.doubleValue
        s.crt = crtCheck.state == .on
        s.glitches = glitchCheck.state == .on
        s.fps = Settings.frameRates[fpsPopup.indexOfSelectedItem]
        s.mainDisplayOnly = displayPopup.indexOfSelectedItem == 1
        s.clock = clockCheck.state == .on
        s.intro = introCheck.state == .on
        s.introText = introField.stringValue
        s.messages = messagesCheck.state == .on
        s.messageText = messagesField.stringValue
        s.save()
        // Update the preview (and any other instance in this process) straight away.
        NotificationCenter.default.post(name: .matrixOptionsChanged, object: nil)
        close()
    }

    @objc private func cancelSheet() {
        close()
    }

    private func close() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
        if Self.current === self { Self.current = nil }
    }
}
