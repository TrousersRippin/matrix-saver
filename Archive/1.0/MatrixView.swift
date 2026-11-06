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
    static let speedRange = 0.25...3.0
    static let densityRange = 0.2...3.0
    static let sizeRange = 0.5...3.0

    // What 1.00× on the sliders means, relative to the original tuning.
    static let densityScale = 1.75
    static let sizeScale = 0.75

    var colorIndex = 0
    var speed = 1.0     // multiplier on fall speed
    var density = 1.0   // multiplier on number of streams
    var size = 1.0      // multiplier on glyph size

    private static let store = ScreenSaverDefaults(forModuleWithName: "local.agentsmith.MatrixSaver")

    static func load() -> Settings {
        guard let d = store else { return Settings() }
        d.synchronize()  // pick up values saved by the Options sheet in another process
        d.register(defaults: ["colorIndex": 0, "speed": 1.0, "density": 1.0, "size": 1.0])
        return Settings(colorIndex: min(max(0, d.integer(forKey: "colorIndex")), palette.count - 1),
                        speed: d.double(forKey: "speed").clamped(to: speedRange),
                        density: d.double(forKey: "density").clamped(to: densityRange),
                        size: d.double(forKey: "size").clamped(to: sizeRange))
    }

    func save() {
        guard let d = Self.store else { return }
        d.set(colorIndex, forKey: "colorIndex")
        d.set(speed, forKey: "speed")
        d.set(density, forKey: "density")
        d.set(size, forKey: "size")
        d.synchronize()
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

/// Digital-rain screensaver. Each column has a fading brightness trail; glyphs are
/// pre-rendered (mirrored, with glow) into small images so a frame is just blits.
/// The Objective-C name is deliberately distinctive: every saver shown in System Settings is
/// loaded into one legacyScreenSaver process, and a clash with another saver's "MatrixView"
/// class means the wrong one gets used.
@objc(AgentSmithMatrixView)
final class MatrixView: ScreenSaverView {
    private struct Drop {
        var col: Int
        var y: Float        // head position in rows (fractional)
        var speed: Float    // rows per second
        var lastRow: Int    // last row the head lit
    }

    private static let glyphStrings: [String] = {
        var s = (0xFF66...0xFF9D).compactMap { UnicodeScalar($0).map { String($0) } }  // half-width katakana
        s += "0123456789Z:.=*+-<>¦|\"".map(String.init)
        return s
    }()

    private var settings = Settings.load()

    private var cellW: CGFloat = 0
    private var cellH: CGFloat = 0
    private var pad: CGFloat = 0
    private var cols = 0
    private var rows = 0
    private var laidOutSize: CGSize = .zero

    private var chars: [UInt16] = []      // glyph index per cell (row-major)
    private var bright: [Float] = []      // 0...1 per cell
    private var fade: [Float] = []        // brightness lost per second, per column
    private var drops: [Drop] = []

    private var trailGlyphs: [CGImage] = []
    private var headGlyphs: [CGImage] = []
    private var lastTime: CFTimeInterval = 0

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
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
        chars = []
        bright = []
        fade = []
        drops = []
        trailGlyphs = []
        headGlyphs = []
        cols = 0
        rows = 0
        laidOutSize = .zero  // lay out afresh if this instance is ever drawn again
    }

    // MARK: - Layout

    private func layout(for size: CGSize) {
        laidOutSize = size
        let baseSize = isPreview ? 7 : max(14, size.height / 55)
        let fontSize = max(5, (baseSize * CGFloat(settings.size * Settings.sizeScale)).rounded())
        cellW = (fontSize * 0.72).rounded()
        cellH = (fontSize * 1.08).rounded()
        pad = (fontSize * 0.5).rounded()
        cols = max(1, Int(ceil(size.width / cellW)))
        rows = max(1, Int(ceil(size.height / cellH)))

        let n = Self.glyphStrings.count
        chars = (0..<(cols * rows)).map { _ in UInt16.random(in: 0..<UInt16(n)) }
        bright = Array(repeating: 0, count: cols * rows)
        fade = (0..<cols).map { _ in randomFade() }
        drops = (0..<max(1, Int(Double(cols) * 0.9 * settings.density * Settings.densityScale))).map { _ in
            var d = newDrop()
            d.y = -Float.random(in: 0...Float(rows))
            d.lastRow = Int(floor(d.y))
            return d
        }

        let c = Settings.palette[settings.colorIndex]
        let toWhite: (CGFloat) -> CGFloat = { $0 + (1 - $0) * 0.85 }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        trailGlyphs = renderGlyphs(fontSize: fontSize, scale: scale,
                                   color: CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1),
                                   glow: CGColor(srgbRed: c.r * 0.8, green: c.g * 0.8, blue: c.b * 0.8, alpha: 0.7))
        headGlyphs = renderGlyphs(fontSize: fontSize, scale: scale,
                                  color: CGColor(srgbRed: toWhite(c.r), green: toWhite(c.g), blue: toWhite(c.b), alpha: 1),
                                  glow: CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
    }

    // Fade scales with speed so trail length stays the same at any speed.
    private func randomFade() -> Float { Float.random(in: 0.35...0.85) * Float(settings.speed) }

    private func newDrop() -> Drop {
        let y = -Float.random(in: 0...Float(rows) * 0.6)
        return Drop(col: Int.random(in: 0..<cols), y: y,
                    speed: Float.random(in: 9...26) * Float(settings.speed), lastRow: Int(floor(y)))
    }

    private func renderGlyphs(fontSize: CGFloat, scale: CGFloat, color: CGColor, glow: CGColor) -> [CGImage] {
        let font = CTFontCreateWithName("HiraginoSans-W4" as CFString, fontSize, nil)
        let imgW = cellW + pad * 2
        let imgH = cellH + pad * 2
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        return Self.glyphStrings.compactMap { str in
            guard let ctx = CGContext(data: nil, width: Int(imgW * scale), height: Int(imgH * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: imgW, y: 0)
            ctx.scaleBy(x: -1, y: 1)  // mirrored glyphs, as in the film
            ctx.setShadow(offset: .zero, blur: fontSize * 0.45, color: glow)

            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
            let line = CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, str as CFString, attrs as CFDictionary))
            let gb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: pad + (cellW - gb.width) / 2 - gb.minX,
                                       y: pad + cellH * 0.18)
            CTLineDraw(line, ctx)
            return ctx.makeImage()
        }
    }

    // MARK: - Animation

    override func startAnimation() {
        super.startAnimation()
        // legacyScreenSaver may reuse an instance created before the options were changed
        // (possibly in another process), so pick up the latest saved options each time.
        let latest = Settings.load()
        if latest != settings {
            settings = latest
            laidOutSize = .zero
        }
        lastTime = CACurrentMediaTime()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, max(0, now - lastTime)))
        lastTime = now
        step(dt)
        setNeedsDisplay(bounds)
    }

    private func step(_ dt: Float) {
        guard cols > 0, dt > 0 else { return }
        let glyphCount = UInt16(Self.glyphStrings.count)

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
                if r >= 0 && r < rows {
                    let idx = r * cols + drops[i].col
                    bright[idx] = 1
                    chars[idx] = UInt16.random(in: 0..<glyphCount)
                }
            }
            if drops[i].lastRow >= rows + 4 {
                drops[i] = newDrop()
                fade[drops[i].col] = randomFade()
            }
        }

        // Occasional glyph mutation within trails.
        let mutations = max(1, Int(Float(cols * rows) * 0.25 * dt))
        for _ in 0..<mutations {
            chars[Int.random(in: 0..<chars.count)] = UInt16.random(in: 0..<glyphCount)
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if bounds.size != laidOutSize { layout(for: bounds.size) }

        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(bounds)
        guard !trailGlyphs.isEmpty else { return }

        let imgW = cellW + pad * 2
        let imgH = cellH + pad * 2
        let top = bounds.height

        for r in 0..<rows {
            let y = top - CGFloat(r + 1) * cellH - pad
            let base = r * cols
            for c in 0..<cols {
                let b = bright[base + c]
                if b < 0.02 { continue }
                ctx.setAlpha(CGFloat(b * b))
                ctx.draw(trailGlyphs[Int(chars[base + c])],
                         in: CGRect(x: CGFloat(c) * cellW - pad, y: y, width: imgW, height: imgH))
            }
        }

        ctx.setAlpha(1)
        for d in drops where d.lastRow >= 0 && d.lastRow < rows {
            let idx = d.lastRow * cols + d.col
            let y = top - CGFloat(d.lastRow + 1) * cellH - pad
            ctx.draw(headGlyphs[Int(chars[idx])],
                     in: CGRect(x: CGFloat(d.col) * cellW - pad, y: y, width: imgW, height: imgH))
        }
    }

    // MARK: - Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? { OptionsController.present() }

    @objc private func optionsDidChange() {
        settings = Settings.load()
        laidOutSize = .zero  // force re-layout with the new options
        setNeedsDisplay(bounds)
    }
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
    private var colorPopup: NSPopUpButton!
    private var speedSlider: NSSlider!
    private var densitySlider: NSSlider!
    private var speedLabel: NSTextField!
    private var densityLabel: NSTextField!
    private var sizeSlider: NSSlider!
    private var sizeLabel: NSTextField!

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

        // Sizes a control to fit, then centres it vertically in row `row` at x.
        func place(_ v: NSControl, row: CGFloat, x: CGFloat, width w: CGFloat? = nil) {
            v.sizeToFit()
            let h = v.frame.height
            v.frame = NSRect(x: x, y: margin + row * rowH + (rowH - h) / 2, width: w ?? v.frame.width, height: h)
            content.addSubview(v)
        }
        func label(_ text: String, row: CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            place(l, row: row, x: margin, width: labelW)
        }
        func slider(_ range: ClosedRange<Double>, row: CGFloat) -> NSSlider {
            let s = NSSlider(value: 1, minValue: range.lowerBound, maxValue: range.upperBound,
                             target: self, action: #selector(sliderChanged(_:)))
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

        label("Colour:", row: 0)
        colorPopup = NSPopUpButton()
        colorPopup.addItems(withTitles: Settings.palette.map(\.name))
        for (item, c) in zip(colorPopup.itemArray, Settings.palette) {
            item.image = swatch(NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
        }
        place(colorPopup, row: 0, x: controlX - 3, width: controlW * 0.75)

        label("Speed:", row: 1)
        speedSlider = slider(Settings.speedRange, row: 1)
        speedLabel = valueLabel(row: 1)
        label("Density:", row: 2)
        densitySlider = slider(Settings.densityRange, row: 2)
        densityLabel = valueLabel(row: 2)
        label("Font size:", row: 3)
        sizeSlider = slider(Settings.sizeRange, row: 3)
        sizeLabel = valueLabel(row: 3)

        // Credit line. Bundle.main is the host process here, so look up the saver's own bundle.
        let version = Bundle(for: OptionsController.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let credit = NSTextField(labelWithString: "Version \(version) · Agent Smith")
        credit.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        credit.textColor = .secondaryLabelColor
        credit.alignment = .center
        place(credit, row: 4, x: margin, width: width - margin * 2)

        // Button row: Defaults on the left, Cancel and OK on the right.
        let buttonRow: CGFloat = 5
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

    private func show(_ s: Settings) {
        colorPopup.selectItem(at: s.colorIndex)
        speedSlider.doubleValue = s.speed
        densitySlider.doubleValue = s.density
        sizeSlider.doubleValue = s.size
        sliderChanged(nil)
    }

    @objc private func sliderChanged(_ sender: Any?) {
        speedLabel.stringValue = String(format: "%.2f×", speedSlider.doubleValue)
        densityLabel.stringValue = String(format: "%.2f×", densitySlider.doubleValue)
        sizeLabel.stringValue = String(format: "%.2f×", sizeSlider.doubleValue)
    }

    @objc private func resetDefaults() {
        show(Settings())
    }

    @objc private func saveSheet() {
        Settings(colorIndex: colorPopup.indexOfSelectedItem,
                 speed: speedSlider.doubleValue,
                 density: densitySlider.doubleValue,
                 size: sizeSlider.doubleValue).save()
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
