import AppKit
import CoreText
import ScreenSaver
import os

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
    /// Fall speed at 1.00×, relative to versions up to 3.4. Scales drops and fade together, so
    /// trail length doesn't change.
    static let baseSpeed: Float = 0.8
    static let densityRange = 0.2...3.0
    static let sizeRange = 0.5...3.0
    static let glowRange = 0.0...2.0
    static let frameRates = [15, 30, 60]

    static let charsets = ["Film", "Binary", "Latin", "Custom", "Logs"]
    static let customCharset = 3
    static let logCharset = 4
    static let defaultLogPath = "/var/log/install.log"
    static let defaultKeywords = "error, fail, denied, fatal, crash, panic"
    static let defaultLokiQuery = #"{service_name=~"traefik|postgres|loki"}"#

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
    var logPath = Settings.defaultLogPath
    var keywords = Settings.defaultKeywords
    var levelColors = true  // log mode: colour lines by log level
    var followVolume = true // log mode: more rain while logs are busy, less while quiet
    var errorRipple = true  // log mode: a ripple spreads from each new error line
    var errorBanner = true  // log mode: each new error line is written across the screen
    var logSource = 0   // 0: a file, 1: a Loki server
    var lokiURL = ""
    var lokiQuery = Settings.defaultLokiQuery

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
                              "customChars": base.customChars, "logPath": base.logPath, "keywords": base.keywords, "levelColors": base.levelColors, "followVolume": base.followVolume, "errorRipple": base.errorRipple, "errorBanner": base.errorBanner, "logSource": base.logSource, "lokiURL": base.lokiURL,
                              "lokiQuery": base.lokiQuery, "depth": base.depth, "glow": base.glow,
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
        s.logPath = d.string(forKey: "logPath") ?? base.logPath
        s.keywords = d.string(forKey: "keywords") ?? base.keywords
        s.levelColors = d.bool(forKey: "levelColors")
        s.followVolume = d.bool(forKey: "followVolume")
        s.errorRipple = d.bool(forKey: "errorRipple")
        s.errorBanner = d.bool(forKey: "errorBanner")
        s.logSource = d.integer(forKey: "logSource").clamped(to: 0...1)
        s.lokiURL = d.string(forKey: "lokiURL") ?? base.lokiURL
        s.lokiQuery = d.string(forKey: "lokiQuery") ?? base.lokiQuery
        // The Loki test build took a Loki address in the log file field.
        let path = s.logPath.trimmingCharacters(in: .whitespaces).lowercased()
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            if s.lokiURL.isEmpty { s.lokiURL = s.logPath.trimmingCharacters(in: .whitespaces) }
            s.logSource = 1
            s.logPath = base.logPath
        }
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
        d.set(logPath, forKey: "logPath")
        d.set(keywords, forKey: "keywords")
        d.set(levelColors, forKey: "levelColors")
        d.set(followVolume, forKey: "followVolume")
        d.set(errorRipple, forKey: "errorRipple")
        d.set(errorBanner, forKey: "errorBanner")
        d.set(logSource, forKey: "logSource")
        d.set(lokiURL, forKey: "lokiURL")
        d.set(lokiQuery, forKey: "lokiQuery")
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

    /// The log file to rain, with ~ expanded. A blank path means the default.
    var logFile: String {
        let p = logPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return ((p.isEmpty ? Self.defaultLogPath : p) as NSString).expandingTildeInPath
    }

    /// Where log rain comes from. A blank query means the default.
    var logSourceValue: LogSource {
        guard logSource == 1 else { return .file(logFile) }
        let q = lokiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return .loki(url: lokiURL.trimmingCharacters(in: .whitespacesAndNewlines), query: q.isEmpty ? Self.defaultLokiQuery : q)
    }

    /// The keywords to show in red in log text: comma separated, matched ignoring case.
    var keywordList: [String] {
        keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) } }
    }

    /// The colours log text keeps after tinting, indexed by `Layer.Ink` (nil: tinted with the rain).
    /// Keywords and error lines are red, warnings amber; either turns white when the rain is already
    /// near that colour (including while Colour Cycle passes through it). Keywords on an error line
    /// are white so they still stand out.
    func inkColors(cycleHue: Double) -> [CGColor?] {
        let hue: Double? = colorIndex == Self.customColorIndex ? customHue
            : colorIndex == Self.cycleColorIndex ? cycleHue : nil
        let reddish = colorIndex == 4 || hue.map { $0 < 0.06 || $0 > 0.94 } == true
        let amberish = colorIndex == 5 || hue.map { $0 >= 0.06 && $0 < 0.18 } == true
        let white = CGColor(gray: 1, alpha: 1)
        let red = reddish ? white : CGColor(srgbRed: 1, green: 0.22, blue: 0.18, alpha: 1)
        let amber = amberish ? white : CGColor(srgbRed: 1, green: 0.68, blue: 0.1, alpha: 1)
        return [nil, red, red, amber, nil, white]
    }

    /// The rain's characters, and whether they are mirrored as in the film. Latin, custom and log
    /// text stays readable. An empty custom set falls back to the film's characters. Logs use
    /// printable ASCII in code order, so glyph index = scalar - 0x20 (see LogFeed).
    var glyphs: (strings: [String], mirrored: Bool) {
        switch charset {
        case Self.logCharset: return ((0x20...0x7E).map { String(UnicodeScalar(UInt8($0))) }, false)
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

/// Where log rain comes from: a file on this Mac, or a Loki server and a LogQL query.
private enum LogSource: Equatable {
    case file(String)
    case loki(url: String, query: String)
}

/// Log lines for the rain to spell out, as glyph indices (scalar - 0x20, so 0 is a space), with
/// `LogFeed.keywordBit` set on letters that are part of a keyword and the line's log level in
/// `levelBits`. New lines are shown first, then the history loops. History is kept per service
/// (a file is one), and drops take turns between services, so a busy one doesn't drown the rest.
///
/// Files: reads the end of the file, then picks up appended lines. legacyScreenSaver's sandbox
/// allows read-only access to the whole disk, so this is only limited by Unix permissions.
/// Loki: fetches the last day of the query, then polls for newer lines. The sandbox allows
/// outgoing connections, and plain http works to an IP address.
private final class LogFeed {
    static let tailBytes: UInt64 = 256 * 1024
    static let maxHistory = 3000            // file: lines kept
    static let serviceHistory = 300         // loki: lines kept per service
    static let lokiStartLimit = 2000        // loki: lines per start fetch
    static let lokiStartRounds = 5          // loki: start fetches at most (see receive)
    static let maxLineLength = 200         // glyphs shown per line (see cut)
    static let maxEncoded = 800            // glyphs encoded per line, for its shape (see store)
    static let keywordBit: UInt16 = 0x8000
    static let levelShift: UInt16 = 13     // bits 13-14: the line's Level
    static let levelBits: UInt16 = 0x6000
    static let glyphBits: UInt16 = 0x1FFF

    enum Level: UInt16 { case normal = 0, error, warn, debug }
    static let lokiHistory: Double = 24 * 3600  // seconds fetched at start
    // A line can reach Loki after a newer one (agents batch and retry), so each poll asks again
    // for this much before the newest timestamp seen, and skips the entries it already has.
    static let lokiOverlap: UInt64 = 30_000_000_000  // nanoseconds
    // Loki logs every query it runs, with the query text. Every poll carries this tag and filters
    // it out, so those lines about the saver's own polls don't show up in the rain. Loki also runs
    // a stats lookup per query on the stream selector alone, which loses the tag; those lines are
    // housekeeping noise, so they are left out too. And the first fetch (a day, newest first) is
    // split into hourly subqueries that Loki cancels once it has enough lines; each cancel logs
    // level=error lines ("context canceled", "err=EOF") without the tag, which would rain as red
    // errors and set off a ripple every time the saver starts.
    static let lokiFilters = #" != "matrix-saver-poll" != "query_type=stats""#
        + #" !~ "caller=(scheduler_processor|errors).go.*(context canceled|err=EOF)""#

    let source: LogSource
    let keywordList: [String]
    let levels: Bool                  // colour by log level (levels are always marked, for ripples)
    private let keywords: [[UInt16]]  // lowercased, as glyph indices
    /// The lines kept from one service (Loki's service_name; a file is one source, named "").
    private struct Source {
        var lines: [[UInt16]] = []
        var shapes: [Int] = []           // shape(of:) of each line
        var cursor = 0
        var credit = 0.0                 // for taking turns, see nextLine
    }
    private var sources: [Source] = []
    private var sourceIndex: [String: Int] = [:]
    private var fresh: [[UInt16]] = []   // arrived since the saver started
    private var placeholder = false      // the history is a status message, not log lines
    private var lastPoll: CFTimeInterval = 0

    private var offset: UInt64 = 0       // file: position read up to (always just after a newline)
    private var fileID: UInt64?          // file: its inode, to notice a new file at the path
    private var lokiSince: UInt64 = 0    // loki: newest timestamp received, in nanoseconds
    private var lokiSeen: [(ts: UInt64, id: Int)] = []  // loki: entries in the overlap, oldest first
    private var lokiSeenIDs: Set<Int> = []
    private var lokiBusy = false         // loki: a request is in flight
    private var lokiOK = false           // loki: has answered at least once

    private let started = CACurrentMediaTime()
    private var arrivals: [(t: CFTimeInterval, n: Int)] = []  // new lines in the last volumeWindow
    private var seedCount = 0            // new lines before the usual rate is known (file)
    private var baseline: Double?        // usual lines per second (slow average)
    private var lastVolume: CFTimeInterval = 0
    /// How busy the log is now compared with usual: 1 is usual, more when busier. See updateVolume.
    private(set) var volume: Double = 1

    private static let log = Logger(subsystem: "local.agentsmith.MatrixSaver", category: "logs")

    /// One feed shared by every saver view in the process: System Settings shows several previews
    /// and the saver has a view per display, and the server should be polled once, not per view.
    private static weak var current: LogFeed?

    static func shared(_ source: LogSource, keywords: [String], levels: Bool) -> LogFeed {
        if let f = current, f.source == source, f.keywordList == keywords, f.levels == levels { return f }
        let f = LogFeed(source: source, keywords: keywords, levels: levels)
        current = f
        return f
    }

    private init(source: LogSource, keywords: [String], levels: Bool) {
        self.source = source
        keywordList = keywords
        self.levels = levels
        self.keywords = keywords.map { $0.unicodeScalars.map { UInt16($0.value - 0x20) } }
        switch source {
        case .file(let path): loadFile(path)
        case .loki:
            setStatus("CONNECTING TO LOKI")
            fetchLoki()
        }
    }

    /// The next line for a new drop: new lines first, then the history, looping through each
    /// source's lines in order. `isNew` is true for a line that has just arrived.
    ///
    /// Sources take turns (smooth weighted round-robin: each earns its weight in credit per line,
    /// the one with most credit goes and pays the total). The weight is the square root of the
    /// lines a source has, so a service with 300 lines comes up about 5× as often as one with 10,
    /// not 30×: quiet services get seen, and their few lines don't repeat on every turn.
    func nextLine() -> (text: [UInt16], isNew: Bool) {
        if !fresh.isEmpty { return (fresh.removeFirst(), true) }
        var total = 0.0
        var best = -1
        for i in sources.indices where !sources[i].lines.isEmpty {
            let w = Double(sources[i].lines.count).squareRoot()
            total += w
            sources[i].credit += w
            if best < 0 || sources[i].credit > sources[best].credit { best = i }
        }
        guard best >= 0 else { return ([], false) }
        sources[best].credit -= total
        if sources[best].cursor >= sources[best].lines.count { sources[best].cursor = 0 }
        defer { sources[best].cursor += 1 }
        return (sources[best].lines[sources[best].cursor], false)
    }

    private var historyCap: Int {
        if case .file = source { return Self.maxHistory }
        return Self.serviceHistory
    }

    private func clearSources() {
        sources = []
        sourceIndex = [:]
        placeholder = false
    }

    /// Adds lines to a source's history (or replaces it), keeping the newest `historyCap`.
    /// Lines that differ only in numbers are kept once (see shape(of:)): a new one replaces the
    /// older one and moves to the newest end, so a message that repeats every few seconds doesn't
    /// fill its source's share and push out the lines that differ.
    private func store(_ lines: [[UInt16]], in key: String, replace: Bool = false) {
        let i: Int
        if let j = sourceIndex[key] {
            i = j
        } else {
            i = sources.count
            sources.append(Source())
            sourceIndex[key] = i
        }
        // The incoming lines, each shape once (its newest line).
        var incoming: [(text: [UInt16], shape: Int)] = []
        var position: [Int: Int] = [:]
        for line in lines {
            let shape = Self.shape(of: line)  // of the whole line, before it is cut
            if let p = position[shape] { incoming[p].text = []; incoming[p].shape = 0 }
            position[shape] = incoming.count
            incoming.append((Self.cut(line), shape))
        }
        incoming.removeAll { $0.text.isEmpty }
        var src = sources[i]
        if replace {
            src.lines = []
            src.shapes = []
        } else {
            // Drop older lines with the same shape as an incoming one.
            let newShapes = Set(incoming.map(\.shape))
            var keptLines: [[UInt16]] = []
            var keptShapes: [Int] = []
            var cursor = src.cursor
            for (k, line) in src.lines.enumerated() {
                if newShapes.contains(src.shapes[k]) {
                    if k < src.cursor { cursor -= 1 }  // stay on the same line
                } else {
                    keptLines.append(line)
                    keptShapes.append(src.shapes[k])
                }
            }
            src.lines = keptLines
            src.shapes = keptShapes
            src.cursor = cursor
        }
        src.lines += incoming.map(\.text)
        src.shapes += incoming.map(\.shape)
        let dropped = max(0, src.lines.count - historyCap)
        src.lines.removeFirst(dropped)
        src.shapes.removeFirst(dropped)
        src.cursor = replace ? max(0, src.lines.count - 400)  // start near the newest
                             : max(0, src.cursor - dropped)
        sources[i] = src
    }

    /// A line shortened to what is shown. Lines are encoded longer than this so that the shape of
    /// a long line doesn't depend on where the cut falls (numbers of different widths move it).
    static func cut(_ text: [UInt16]) -> [UInt16] {
        guard text.count > maxLineLength else { return text }
        var out = Array(text.prefix(maxLineLength))
        while let last = out.last, last & glyphBits == 0 { out.removeLast() }
        return out
    }

    /// A hash of a line with its numbers folded, to tell repeats (see store). Every run of hex
    /// digits (joined by : . -) that holds a decimal digit (12, 10.1.1.11, a4:cc:5e, 12:04:31)
    /// counts as one "#", so lines that differ only in times, counters, addresses or ports match.
    /// Words like "cafe" or "added" have no digit and are kept as they are. The words are compared
    /// in any order, because some programs (Grafana) write their key=value fields shuffled.
    static func shape(of text: [UInt16]) -> Int {
        var words: [Int] = []
        var h = Hasher()
        var empty = true
        var run: [UInt16] = []
        var runHasDigit = false
        func flush() {
            if runHasDigit { h.combine(UInt16(0xFFFF)) } else { for g in run { h.combine(g) } }
            if !run.isEmpty { empty = false }
            run.removeAll(keepingCapacity: true)
            runHasDigit = false
        }
        func endWord() {
            flush()
            if !empty { words.append(h.finalize()) }
            h = Hasher()
            empty = true
        }
        for raw in text {
            let g = raw & glyphBits             // glyph index = scalar - 0x20
            if g == 0 { endWord(); continue }   // space
            let digit = g >= 0x10 && g <= 0x19                    // 0-9
            let hex = digit || (g >= 0x41 && g <= 0x46) || (g >= 0x21 && g <= 0x26)  // a-f, A-F
            let joiner = g == 0x1A || g == 0x0E || g == 0x0D                         // : . -
            if hex || (joiner && !run.isEmpty) {
                run.append(g)
                runHasDigit = runHasDigit || digit
            } else {
                flush()
                h.combine(g)
                empty = false
            }
        }
        endWord()
        var line = Hasher()
        for w in words.sorted() { line.combine(w) }
        return line.finalize()
    }

    private var lineCount: Int { sources.reduce(0) { $0 + $1.lines.count } }

    static func level(of text: [UInt16]) -> Level {
        Level(rawValue: ((text.first ?? 0) & levelBits) >> levelShift) ?? .normal
    }

    /// Checks for new lines every few seconds (every ten while Loki can't be reached).
    func poll() {
        let now = CACurrentMediaTime()
        updateVolume(now)
        switch source {
        case .file(let path):
            guard now - lastPoll > 3 else { return }
            lastPoll = now
            pollFile(path)
        case .loki:
            guard !lokiBusy, now - lastPoll > (lokiOK ? 3 : 10) else { return }
            lastPoll = now
            fetchLoki()
        }
    }

    private func setStatus(_ message: String) {
        clearSources()
        store([encode(message, level: .normal)], in: "")
        placeholder = true
    }

    /// Adds newly arrived lines: shown next, and kept in their source's history.
    private func append(_ lines: [(key: String, text: [UInt16])]) {
        guard !lines.isEmpty else { return }
        if placeholder { clearSources() }
        fresh = Array((fresh + lines.map { Self.cut($0.text) }).suffix(200))
        arrivals.append((CACurrentMediaTime(), lines.count))
        if baseline == nil { seedCount += lines.count }
        for (key, group) in Dictionary(grouping: lines, by: \.key) { store(group.map(\.text), in: key) }
    }

    // MARK: Volume

    static let volumeWindow: Double = 20          // seconds of new lines that count as "now"
    static let seedTime: Double = 60              // file: the first minute sets the usual rate
    static let baselineTime: Double = 15 * 60     // how slowly "usual" follows the log
    static let minRate: Double = 1.0 / 60         // a line a minute: quieter than this is quiet
    static let volumeRange = 0.5...2.5

    /// Compares the rate of new lines over the last minute with the usual rate, and sets `volume`
    /// to the square root of that ratio (gentler than linear), clamped to `volumeRange`. The usual
    /// rate comes from Loki's history at start, or, for a file, the first minute; after that it
    /// follows the log over about a quarter of an hour. A burst moves it at most as if the rate
    /// were 3× usual, so one busy spell doesn't make the quiet after it look unusually quiet.
    private func updateVolume(_ now: CFTimeInterval) {
        guard now - lastVolume >= 1 else { return }
        let dt = lastVolume == 0 ? 0 : now - lastVolume
        lastVolume = now
        arrivals.removeAll { now - $0.t > Self.volumeWindow }
        guard !placeholder else { volume = 1; return }
        let recent = Double(arrivals.reduce(0) { $0 + $1.n }) / Self.volumeWindow
        guard let base = baseline else {
            if now - started >= Self.seedTime { baseline = Double(seedCount) / (now - started) }
            volume = 1
            return
        }
        let target = min(recent, max(base, Self.minRate) * 3)
        let usual = base + (target - base) * min(1, dt / Self.baselineTime)
        baseline = usual
        let ratio = max(recent, Self.minRate * 0.1) / max(usual, Self.minRate)
        volume = sqrt(ratio).clamped(to: Self.volumeRange)
    }

    // MARK: File

    /// A file that shrank was rotated: start over.
    /// Reads lines added since the last poll. If more than `tailBytes` arrived, only the last
    /// `tailBytes` are read, from the first line that starts in them.
    /// A rotated log, either a new file at the path (rename-and-create) or the same file cut short
    /// (copy-and-truncate), is read from its start, its lines shown as new; the history is kept.
    /// Lines written to the old file after the last poll and before a rename are missed.
    private func pollFile(_ path: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return }
        let id = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        if size < offset || (fileID != nil && id != fileID) { offset = 0 }
        fileID = id
        guard size > offset else { return }
        let start = max(offset, size > Self.tailBytes ? size - Self.tailBytes : 0)
        append(read(path, from: start, midLine: start > offset).map { ("", $0) })
    }

    private func loadFile(_ path: String) {
        clearSources()
        fresh = []
        offset = 0
        lastPoll = CACurrentMediaTime()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            setStatus("CANNOT READ \(path)")
            return
        }
        fileID = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        let start = size > Self.tailBytes ? size - Self.tailBytes : 0
        store(read(path, from: start, midLine: start > 0), in: "", replace: true)
        if lineCount == 0 {
            let readable = FileHandle(forReadingAtPath: path).map { try? $0.close(); return true } ?? false
            setStatus(readable ? "\(path) IS EMPTY" : "CANNOT READ \(path)")
        }
    }

    /// Reads from `start` to the end of the file, advancing `offset` past the last complete line.
    /// With `midLine`, `start` may fall inside a line: reading begins at the first line that starts
    /// at or after it (one byte earlier is read to tell whether `start` begins a line).
    private func read(_ path: String, from start: UInt64, midLine: Bool = false) -> [[UInt16]] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        let from = midLine && start > 0 ? start - 1 : start
        guard (try? h.seek(toOffset: from)) != nil, let all = try? h.readToEnd(), !all.isEmpty else { return [] }
        var data = all[...]
        if from < start {
            guard let first = data.firstIndex(of: 0x0A) else { return [] }  // no line starts here yet
            data = data[(first + 1)...]
        }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return [] }
        offset = from + UInt64(lastNewline - all.startIndex + 1)
        let lines = data[data.startIndex...lastNewline].split(separator: 0x0A)
        return lines.map { raw in
            let line = Self.stripTimestamp(Self.stripANSI(String(decoding: raw, as: UTF8.self)))
            return self.encode(line, level: Self.level(of: line))
        }.filter { !$0.isEmpty }
    }

    // MARK: Loki

    /// Loki entry: `key` is the source it is kept under (service_name, else the shown name), and
    /// `service` the service_name label, if it has one (only those can be left out of a query).
    /// `id` identifies the entry (time, stream and text), to skip it when a poll returns it again.
    private typealias LokiEntry = (ts: UInt64, line: String, level: Level, key: String, service: String?, id: Int)

    /// Fetches newer lines, or at start (`round` set, or no answer yet) the last day's.
    private func fetchLoki(round: Int = 0, excluding: [String] = [], asOf: UInt64? = nil) {
        guard case let .loki(base, query) = source else { return }
        var root = base
        while root.hasSuffix("/") { root.removeLast() }
        guard var c = URLComponents(string: root + "/loki/api/v1/query_range"), c.host != nil,
              ["http", "https"].contains(c.scheme?.lowercased() ?? "") else {
            setStatus("NOT A LOKI ADDRESS: \(base)")
            return
        }
        let initial = !lokiOK || round > 0
        let now = asOf ?? UInt64(Date().timeIntervalSince1970 * 1e9)
        c.queryItems = [
            URLQueryItem(name: "query", value: Self.query(query, excluding: excluding) + Self.lokiFilters),
            URLQueryItem(name: "start", value: String(initial ? now - UInt64(Self.lokiHistory * 1e9) : lokiSince - min(lokiSince, Self.lokiOverlap))),
            URLQueryItem(name: "end", value: String(now)),
            // At start, the most recent lines; after that, everything newer, oldest first.
            URLQueryItem(name: "limit", value: initial ? String(Self.lokiStartLimit) : "500"),
            URLQueryItem(name: "direction", value: initial ? "backward" : "forward"),
        ]
        // "+" is legal in a query component but servers read it as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = c.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        lokiBusy = true

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var entries: [LokiEntry] = []
            var failure: String?
            if let error {
                failure = error.localizedDescription
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // Loki explains bad queries in the body.
                failure = "HTTP \(http.statusCode) " + String(decoding: (data ?? Data()).prefix(160), as: UTF8.self)
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let body = json["data"] as? [String: Any], let result = body["result"] as? [[String: Any]] {
                for stream in result {
                    let labels = stream["stream"] as? [String: String] ?? [:]
                    let name = labels["container_name"] ?? labels["service_name"] ?? labels["job"] ?? ""
                    let service = labels["service_name"]
                    let labelLevel = LogFeed.level(labels: labels)
                    let streamID = labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
                    for v in stream["values"] as? [[String]] ?? [] where v.count >= 2 {
                        guard let ts = UInt64(v[0]) else { continue }
                        let line = LogFeed.tidy(v[1])
                        var id = Hasher()
                        id.combine(ts)
                        id.combine(streamID)
                        id.combine(v[1])
                        entries.append((ts, name.isEmpty ? line : "\(name): \(line)", labelLevel ?? LogFeed.level(of: line),
                                        service ?? name, service, id.finalize()))
                    }
                }
                entries.sort { $0.ts < $1.ts }
            } else {
                failure = "UNEXPECTED REPLY FROM LOKI"
            }
            DispatchQueue.main.async {
                self?.receive(entries, failure: failure, initial: initial, round: round, excluding: excluding,
                              asOf: now, base: base, query: query)
            }
        }.resume()
    }

    /// At start, the newest lines of a day are mostly the busiest services' (at home, the 2000
    /// newest span half an hour and Postgres has 10 of them). So the start fetch goes in rounds:
    /// after each one, services that have `serviceHistory` lines (or else the one with most) are
    /// left out of the query and it is run again, reaching further back for the rest. It stops
    /// when a round comes back short of the limit (the day is covered) or after `lokiStartRounds`.
    private func receive(_ entries: [LokiEntry], failure: String?, initial: Bool, round: Int,
                         excluding: [String], asOf now: UInt64, base: String, query: String) {
        lokiBusy = false
        if let failure {
            Self.log.error("loki \(base, privacy: .public): \(failure, privacy: .public)")
            if !lokiOK { setStatus("CANNOT REACH \(base): \(failure)") }
            return  // keep showing what we have, and retry
        }
        // The newest time in the reply, even if every entry in it is a repeat (a full reply of
        // repeats still moves on).
        let newest = entries.last?.ts ?? now
        var entries = entries
        if !initial {
            entries.removeAll { lokiSeenIDs.contains($0.id) }  // already had these (the overlap)
        }
        if round == 0 {
            lokiSince = max(lokiSince, newest)
            // Remember what falls in the next poll's overlap.
            let cutoff = lokiSince - min(lokiSince, Self.lokiOverlap)
            for e in entries where e.ts >= cutoff {
                lokiSeen.append((e.ts, e.id))
                lokiSeenIDs.insert(e.id)
            }
            let old = lokiSeen.prefix { $0.ts < cutoff }
            for e in old { lokiSeenIDs.remove(e.id) }
            lokiSeen.removeFirst(old.count)
        }
        let lines = entries.compactMap { e -> (key: String, text: [UInt16])? in
            let text = encode(e.line, level: e.level)
            return text.isEmpty ? nil : (e.key, text)
        }
        guard initial else { append(lines); return }

        if round == 0 {
            lokiOK = true
            // The usual rate: lines over the time they span (the fetch is capped, so may not be a day).
            if let first = entries.first?.ts, entries.count > 1, now > first {
                baseline = Double(entries.count) / max(Self.volumeWindow, Double(now - first) / 1e9)
            } else {
                baseline = 0
            }
            if lines.isEmpty {
                setStatus("NO LOG LINES IN THE LAST DAY FOR \(query)")
                return
            }
            clearSources()
        }
        // A later round reaches further back with the same end, so it has all the earlier lines of
        // the services it includes.
        for (key, group) in Dictionary(grouping: lines, by: \.key) { store(group.map(\.text), in: key, replace: true) }

        guard entries.count >= Self.lokiStartLimit, round + 1 < Self.lokiStartRounds else { return }
        var counts: [String: Int] = [:]
        for e in entries { if let s = e.service { counts[s, default: 0] += 1 } }
        var full = counts.filter { $0.value >= Self.serviceHistory }.map(\.key)
        if full.isEmpty, let top = counts.max(by: { $0.value < $1.value }) { full = [top.key] }
        guard !full.isEmpty else { return }
        fetchLoki(round: round + 1, excluding: excluding + full.sorted(), asOf: now)
    }

    /// The query with `service_name!~"a|b"` added to its stream selector, leaving those out.
    static func query(_ query: String, excluding services: [String]) -> String {
        guard !services.isEmpty, let brace = query.firstIndex(of: "{") else { return query }
        let pattern = services.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let literal = pattern.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var q = query
        q.insert(contentsOf: "service_name!~\"\(literal)\", ", at: q.index(after: brace))
        return q
    }

    // MARK: Cleaning up lines

    // Leading timestamps eat most of a column and repeat line after line, so drop them: ISO dates
    // ("2026-11-06 10:22:01+01", "2026-11-06 11:24:51.319 CET", but not a level such as "INF" in
    // that place) and syslog dates
    // ("Fri Nov  6 10:28:56.515"). Drop the host name after one too ("macbook-pro Safari[53369]:"
    // keeps "Safari[53369]:").
    private static let timestamp = try! NSRegularExpression(pattern:
        #"^(\d{4}-\d{2}-\d{2}[ T][\d:.]+(Z|[+-]\d{2}:?\d{0,2})?( (?!(INF|ERR|WRN|DBG|TRC|FTL|PNC|INFO|WARN|ERROR|DEBUG|TRACE|FATAL|PANIC|CRIT)\b)[A-Z]{3,5})?|([A-Z][a-z]{2} )?[A-Z][a-z]{2} +\d{1,2} \d\d:\d\d:\d\d(\.\d+)?)\s+(\S+ (?=[^\s\[]+\[\d+\]:))?"#)
    // logfmt fields that are noise in the rain: timestamps (Loki has its own), source locations, ids.
    private static let logfmtNoise = try! NSRegularExpression(pattern:
        #"(^|\s)(ts|time|caller|org_id|query_hash|traceID|spanID)=("[^"]*"|\S+)"#)
    // A word repeated straight after itself, like "UCG-Fiber UCG-Fiber".
    private static let repeatedWord = try! NSRegularExpression(pattern: #"(?<=^|\s)(\S{3,}) \1(?=\s|$)"#)

    static func stripTimestamp(_ line: String) -> String {
        replace(timestamp, in: line, with: "")
    }

    private static func replace(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Makes a line from Loki readable in the rain: JSON becomes "level message key=value", logfmt
    /// loses its noise fields. The caller prefixes it with the container it came from.
    static func tidy(_ raw: String) -> String {
        var line = stripANSI(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("{"), let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
            let skip: Set = ["level", "lvl", "msg", "message", "time", "ts", "timestamp", "@timestamp"]
            var parts: [String] = []
            if let level = (obj["level"] ?? obj["lvl"]) as? String { parts.append(level) }
            if let message = (obj["msg"] ?? obj["message"]) as? String { parts.append(message) }
            for (k, v) in obj.sorted(by: { $0.key < $1.key }) where !skip.contains(k) { parts.append("\(k)=\(v)") }
            line = parts.joined(separator: " ")
        } else {
            line = replace(logfmtNoise, in: line, with: "")
        }
        line = stripTimestamp(line.trimmingCharacters(in: .whitespaces))
        return replace(repeatedWord, in: line, with: "$1")
    }

    // MARK: Log levels

    // Terminal colour codes, as in "[\u{1B}[32minfo\u{1B}[39m]": the escape has no glyph and the rest
    // would rain as "[32m".
    private static let ansi = try! NSRegularExpression(pattern: #"\x1B\[[0-9;?]*[A-Za-z]"#)
    // "level=warn", "lvl: error", "severity=ERROR", "loglevel=debug".
    private static let levelField = try! NSRegularExpression(pattern:
        #"(?i)(?:^|[\s{,])(?:level|lvl|severity|loglevel)\s*[=:]\s*"?([a-z]+)"#)
    // A word that may be a level: letters alone, with anything but letters, digits, "_", "=" or "-"
    // around it, so "errors=0" and "error-page" don't count.
    private static let levelWord = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_=-])([A-Za-z]{3,9})(?![A-Za-z0-9_=-])"#)
    // glog: "E1114 10:00:00.123456 ..."
    private static let glog = try! NSRegularExpression(pattern: #"^([EWIF])\d{4} "#)
    // CEF (UniFi SIEM): "CEF:0|vendor|product|version|id|name|severity|"
    private static let cef = try! NSRegularExpression(pattern: #"CEF:\d+(?:\|[^|]*){5}\|(\d+)\|"#)

    static func stripANSI(_ s: String) -> String {
        s.contains("\u{1B}") ? replace(ansi, in: s, with: "") : s
    }

    private static func level(word: String) -> Level? {
        switch word.lowercased() {
        case "error", "err", "eror", "erro", "fatal", "fatl", "ftl", "crit", "critical", "crt", "panic",
             "pnc", "alert", "emerg", "emergency", "severe": return .error
        case "warn", "warning", "wrn", "wrng": return .warn
        case "debug", "dbg", "dbug", "trace", "trc", "trce", "verbose", "vrb": return .debug
        case "info", "inf", "information", "notice", "log": return .normal
        default: return nil
        }
    }

    /// CEF severity 0-10: 7 and up is high, 5-6 medium.
    private static func level(cefSeverity n: Int) -> Level {
        n >= 7 ? .error : n >= 5 ? .warn : .normal
    }

    /// The level from Loki's stream labels, if it has one: `detected_level` or `level`, or a numeric
    /// CEF `severity` as UniFi's SIEM sends.
    static func level(labels: [String: String]) -> Level? {
        if let w = labels["detected_level"] ?? labels["level"], let l = level(word: w), w != "unknown" { return l }
        if let s = labels["severity"] { return Int(s).map(level(cefSeverity:)) ?? level(word: s) }
        return nil
    }

    /// Guesses a line's level from its text (timestamp and container name already removed). Looks at
    /// a level field, then the first level word in the start of the line: in any case if it is the
    /// first word or bracketed ("[info]", "<warn>", ":INFO:"), but only in capitals elsewhere, so a
    /// message that mentions an error isn't taken for one.
    static func level(of line: String) -> Level {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        if let m = levelField.firstMatch(in: line, range: all), let l = level(word: ns.substring(with: m.range(at: 1))) {
            return l
        }
        if let m = cef.firstMatch(in: line, range: all), let n = Int(ns.substring(with: m.range(at: 1))) {
            return level(cefSeverity: n)
        }
        if let m = glog.firstMatch(in: line, range: all) {
            return ["E": .error, "F": .error, "W": .warn][ns.substring(with: m.range(at: 1))] ?? .normal
        }
        let head = NSRange(location: 0, length: min(ns.length, 80))
        for m in levelWord.matches(in: line, range: head) {
            let r = m.range(at: 1)
            let word = ns.substring(with: r)
            guard let l = level(word: word) else { continue }
            let before = r.location > 0 ? ns.substring(with: NSRange(location: r.location - 1, length: 1)) : ""
            let first = ns.substring(to: r.location).trimmingCharacters(in: .whitespaces).isEmpty
            if first || "[<(|:".contains(before) && !before.isEmpty || word == word.uppercased() { return l }
        }
        return .normal
    }

    private func encode(_ text: String, level: Level) -> [UInt16] {
        var out: [UInt16] = []
        for u in text.unicodeScalars {
            switch u.value {
            case 0x20...0x7E: out.append(UInt16(u.value - 0x20))
            case 0x09: out.append(0)
            default: continue  // other characters have no glyph
            }
            if out.count >= Self.maxEncoded { break }
        }
        while out.last == 0 { out.removeLast() }
        while out.first == 0 { out.removeFirst() }
        markKeywords(&out)
        if level != .normal {
            for i in out.indices { out[i] |= level.rawValue << Self.levelShift }
        }
        return out
    }

    /// How a cell holding glyph value `v` is drawn (see Layer.Ink), ignoring the level unless
    /// `levels` (colour by level) is on.
    static func ink(_ v: UInt16, levels: Bool) -> UInt8 {
        let level = levels ? Level(rawValue: (v & levelBits) >> levelShift) ?? .normal : .normal
        if v & keywordBit != 0 { return level == .error ? Layer.Ink.keywordOnError : Layer.Ink.keyword }
        switch level {
        case .normal: return Layer.Ink.plain
        case .error: return Layer.Ink.error
        case .warn: return Layer.Ink.warn
        case .debug: return Layer.Ink.debug
        }
    }

    /// Sets the keyword bit on every letter of each keyword found, ignoring case.
    private func markKeywords(_ out: inout [UInt16]) {
        guard !keywords.isEmpty, !out.isEmpty else { return }
        // Upper-case letters A-Z are glyphs 0x21...0x3A; lower-case is 0x20 further on.
        let lower = out.map { (0x21...0x3A).contains($0) ? $0 + 0x20 : $0 }
        for word in keywords where word.count <= lower.count {
            for start in 0...(lower.count - word.count) where lower[start] == word[0] {
                if lower[start..<(start + word.count)].elementsEqual(word) {
                    for i in start..<(start + word.count) { out[i] |= Self.keywordBit }
                }
            }
        }
    }
}

/// One plane of rain: a grid of cells with a fading brightness trail per column, and pre-rendered
/// white glyphs. Depth mode stacks three, drawn back to front.
private final class Layer {
    /// How a log cell is drawn: tinted with the rain, dimmed, or in its own colour after tinting
    /// (`inkGlyphs`, colours from `Settings.inkColors`).
    enum Ink {
        static let plain: UInt8 = 0
        static let keyword: UInt8 = 1
        static let error: UInt8 = 2
        static let warn: UInt8 = 3
        static let debug: UInt8 = 4        // tinted, but dim
        static let keywordOnError: UInt8 = 5
        static func coloured(_ ink: UInt8) -> Bool { ink != plain && ink != debug }
    }

    struct Drop {
        var col: Int
        var y: Float        // head position in rows (fractional)
        var speed: Float    // rows per second
        var lastRow: Int    // last row the head lit
        var text: [UInt16] = []  // log mode: the line this drop spells out
        var pos = 0              // log mode: next character of `text`
        var startRow = 0         // log mode: row the text starts at, so columns don't line up
        var idle = false         // parked while the log is quiet (see Layer.active)
        var ripple = false       // log mode: a new error line; ripples (and banners) when it starts to show
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
    var ink: [UInt8] = []         // log mode: how each cell is drawn (Ink)
    var fade: [Float] = []        // brightness lost per second, per column
    var drops: [Drop] = []
    var active = Int.max          // drops in use; the rest finish their fall and park
    var baseDrops = 0             // drops at usual log volume (the Density setting)
    var newErrors: [(col: Int, row: Int, text: [UInt16])] = []  // new error lines that started this step
    var randomGlyphs: UInt16 = 1  // glyphs the rain may pick; message letters follow these
    var feed: LogFeed?            // set in log mode: drops spell its lines instead of random glyphs

    var trailGlyphs: [CGImage] = []  // white, soft glow; tinted with the frame
    var headGlyphs: [CGImage] = []   // white, full glow; tinted with the frame
    var coreGlyphs: [CGImage] = []   // white, no glow; drawn after tinting so heads stay near-white
    var inkGlyphs: [[CGImage]] = []  // log mode: per Ink, glyphs in their colour with glow; drawn after tinting
    var glyphEntries: [(String, Bool)] = []  // what the glyph images show, and whether mirrored
    var fontSize: CGFloat = 0

    init(alpha: CGFloat, speedScale: Float) {
        self.alpha = alpha
        self.speedScale = speedScale
    }

    // Fade scales with speed so trail length stays the same at any speed. Log text falls at the
    // same speed as the other sets but fades more slowly, so its trails are longer to read.
    func randomFade(speed: Float) -> Float {
        Float.random(in: 0.35...0.85) * speed * speedScale * (feed == nil ? 1 : 0.75)
    }

    func newDrop(speed: Float) -> Drop {
        let y = -Float.random(in: 0...Float(rows) * 0.6)
        var d = Drop(col: Int.random(in: 0..<cols), y: y,
                     speed: Float.random(in: 9...26) * speed * speedScale, lastRow: Int(floor(y)))
        if let feed {
            let line = feed.nextLine()
            d.text = line.text
            d.ripple = line.isNew && LogFeed.level(of: line.text) == .error
            d.startRow = Int.random(in: 0...(rows / 3))
        }
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
            if drops[i].idle {
                guard i < active else { continue }
                drops[i] = newDrop(speed: speed)
                fade[drops[i].col] = randomFade(speed: speed)
            }
            drops[i].y += drops[i].speed * dt
            let row = Int(floor(drops[i].y))
            while drops[i].lastRow < row {
                drops[i].lastRow += 1
                let r = drops[i].lastRow
                guard r >= 0 && r < rows else { continue }
                let idx = r * cols + drops[i].col
                if feed != nil {
                    if r < drops[i].startRow { continue }
                    // A spent line ends the drop; its trail fades as usual.
                    guard drops[i].pos < drops[i].text.count else { drops[i].lastRow = rows + 4; break }
                    let v = drops[i].text[drops[i].pos]
                    chars[idx] = v & LogFeed.glyphBits
                    ink[idx] = LogFeed.ink(v, levels: feed?.levels ?? false)
                    if drops[i].ripple {
                        drops[i].ripple = false
                        newErrors.append((drops[i].col, r, drops[i].text))
                    }
                    drops[i].pos += 1
                } else {
                    chars[idx] = UInt16.random(in: 0..<randomGlyphs)
                }
                bright[idx] = 1
            }
            if drops[i].lastRow >= rows + 4 {
                if i >= active {
                    drops[i].idle = true
                    drops[i].lastRow = -1  // no head
                    continue
                }
                drops[i] = newDrop(speed: speed)
                fade[drops[i].col] = randomFade(speed: speed)
            }
        }

        // Occasional glyph mutation within trails, but not in log text, which should stay readable.
        guard feed == nil else { return }
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

    /// A ring spreading from a new error line, lighting the rain it passes. In points, from the
    /// top left.
    private struct Ripple {
        var x: CGFloat
        var y: CGFloat
        var age: Float = 0
    }

    /// A newly arrived error line written across the front layer, left to right, held a few
    /// seconds, then let go letter by letter to fade like any other trail.
    private struct Banner {
        var cells: [(r: Int, c: Int, v: UInt16)]  // letters in reading order: glyph and flags
        var box: (c0: Int, c1: Int, r0: Int, r1: Int)
        var release: [Float]                      // per letter: when it is let go, into the melt
        var age: Float = 0
        static let typeRate: Float = 80           // letters a second
        static let hold: Float = 4                // seconds, once fully written
        static let melt: Float = 1.5              // seconds over which letters are let go
        var typed: Float { Float(cells.count) / Self.typeRate }
        var shown: Int { min(cells.count, Int(age * Self.typeRate)) }
        var melting: Float { max(0, age - typed - Self.hold) }  // seconds into the melt
        var done: Bool { melting >= Self.melt }
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
    private var logFeed: LogFeed?
    private var volumeShown = 1.0       // log volume as the rain shows it (eased); see LogFeed.volume
    private var glyphScale: CGFloat = 2
    private var inkTint: [CGColor?]?   // colours inkGlyphs were rendered in, if any

    private var introLines: [String] = []
    private var introActive = false
    private var introTime = 0.0

    private var clockMinute = -1
    private var clockMask: [Bool] = []
    private var clockBox: (c0: Int, c1: Int, r0: Int, r1: Int)?

    private var messageLetters: [[UInt16]] = []
    private var message: Message?
    private var nextMessage: Float = 0

    private var ripples: [Ripple] = []
    private var lastRipple: CFTimeInterval = 0

    private var banner: Banner?
    private var lastBanner: CFTimeInterval = 0
    private var bannerBox: (c0: Int, c1: Int, r0: Int, r1: Int)?  // cleared behind the banner, until it melts

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
        logFeed = nil
        clockMask = []
        clockBox = nil
        messageLetters = []
        message = nil
        banner = nil
        bannerBox = nil
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
        if settings.charset == Settings.logCharset {
            logFeed = LogFeed.shared(settings.logSourceValue, keywords: settings.keywordList,
                                     levels: settings.levelColors)
        } else {
            logFeed = nil
        }

        // Message letters are added to the front layer only, unmirrored so they can be read.
        let messages = settings.messages ? Settings.lines(settings.messageText).map { Array($0.uppercased().prefix(60)) } : []
        var seen = Set<Character>()
        let letters = messages.flatMap { $0 }.filter { seen.insert($0).inserted }
        var letterIndex: [Character: UInt16] = [:]
        for (i, ch) in letters.enumerated() { letterIndex[ch] = UInt16(strings.count + i) }
        messageLetters = messages.map { $0.compactMap { letterIndex[$0] } }

        let speed = Float(settings.speed) * Settings.baseSpeed
        layers = planes.enumerated().map { i, plane in
            let layer = Layer(alpha: plane.alpha, speedScale: plane.speed)
            layer.feed = logFeed
            let font = max(3, (fontSize * plane.font).rounded())
            layer.cellW = (font * 0.72).rounded()
            layer.cellH = (font * 1.08).rounded()
            layer.pad = (font * 0.5 * max(1, CGFloat(settings.glow))).rounded()
            layer.cols = max(1, Int(ceil(size.width / layer.cellW)))
            layer.rows = max(1, Int(ceil(size.height / layer.cellH)))
            layer.randomGlyphs = UInt16(strings.count)

            layer.chars = (0..<(layer.cols * layer.rows)).map { _ in UInt16.random(in: 0..<layer.randomGlyphs) }
            layer.bright = Array(repeating: 0, count: layer.cols * layer.rows)
            layer.ink = Array(repeating: Layer.Ink.plain, count: layer.cols * layer.rows)
            layer.fade = (0..<layer.cols).map { _ in layer.randomFade(speed: speed) }
            let dropCount = Double(layer.cols) * 0.9 * settings.density * Settings.densityScale * plane.share
            layer.baseDrops = max(1, Int(dropCount))
            // Following log volume, spare drops wait parked for busy spells.
            let following = logFeed != nil && settings.followVolume
            let total = following ? Int(Double(layer.baseDrops) * LogFeed.volumeRange.upperBound) : layer.baseDrops
            layer.active = following ? Int(Double(layer.baseDrops) * volumeShown) : layer.baseDrops
            layer.drops = (0..<total).map { i in
                var d = layer.newDrop(speed: speed)
                d.y = -Float.random(in: 0...Float(layer.rows))
                d.lastRow = Int(floor(d.y))
                d.idle = i >= layer.active
                if d.idle { d.lastRow = -1 }
                return d
            }

            let isFront = i == planes.count - 1
            let entries = strings.map { ($0, mirrored) } + (isFront ? letters.map { (String($0), false) } : [])
            let white = CGColor(gray: 1, alpha: 1)
            layer.trailGlyphs = renderGlyphs(entries, layer: layer, fontSize: font, scale: scale,
                                             glow: CGColor(gray: 0.8, alpha: 0.7))
            layer.headGlyphs = renderGlyphs(entries, layer: layer, fontSize: font, scale: scale, glow: white)
            layer.coreGlyphs = renderGlyphs(entries, layer: layer, fontSize: font, scale: scale, glow: nil)
            layer.glyphEntries = entries
            layer.fontSize = font
            return layer
        }
        glyphScale = scale
        inkTint = nil
        if logFeed != nil, !settings.keywordList.isEmpty || settings.levelColors || settings.errorBanner { renderInkGlyphs() }

        // These all hold positions in the old grid.
        message = nil
        ripples = []
        banner = nil
        bannerBox = nil
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

    /// Renders the glyphs for coloured log text (keywords, error and warning lines). Colour Cycle
    /// calls this again when the hue moves into or out of red or amber. Colours shared by several
    /// inks are rendered once.
    private func renderInkGlyphs() {
        let colors = settings.inkColors(cycleHue: cycleHue)
        inkTint = colors
        for layer in layers {
            var done: [(CGColor, [CGImage])] = []
            layer.inkGlyphs = colors.map { color in
                guard let color else { return [] }
                if let hit = done.first(where: { $0.0 == color }) { return hit.1 }
                let glyphs = renderGlyphs(layer.glyphEntries, layer: layer, fontSize: layer.fontSize,
                                          scale: glyphScale, glow: color.copy(alpha: 0.8), color: color)
                done.append((color, glyphs))
                return glyphs
            }
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
        if settings.colorIndex == Settings.cycleColorIndex, let tint = inkTint,
           settings.inkColors(cycleHue: cycleHue) != tint {
            renderInkGlyphs()
        }

        if introActive {
            introTime += Double(dt)
            if introFrame() == nil { introActive = false }
            return
        }

        if settings.clock { updateClock(front) }
        if let logFeed {
            logFeed.poll()
            if settings.followVolume {
                // Ease towards the feed's volume over a few seconds, so the rain swells and thins.
                volumeShown += (logFeed.volume - volumeShown) * Double(min(1, dt * 0.4))
                for layer in layers { layer.active = Int((Double(layer.baseDrops) * volumeShown).rounded()) }
            }
        }
        if !stepGlitch(dt, front) {
            let speed = Float(settings.speed) * Settings.baseSpeed
            for layer in layers { layer.step(dt, speed: speed) }
        }
        stepBanner(dt, front)  // before stepRipples, which clears newErrors
        stepRipples(dt)
        stepMessage(dt, front)
    }

    // MARK: - Error ripples

    static let rippleLife: Float = 1.6        // seconds
    static let rippleGap: CFTimeInterval = 3  // at least this long between ripples

    private func stepRipples(_ dt: Float) {
        let now = CACurrentMediaTime()
        for layer in layers {
            for p in layer.newErrors where settings.errorRipple && ripples.count < 3 && now - lastRipple >= Self.rippleGap {
                ripples.append(Ripple(x: (CGFloat(p.col) + 0.5) * layer.cellW, y: (CGFloat(p.row) + 0.5) * layer.cellH))
                lastRipple = now
            }
            layer.newErrors = []
        }
        guard !ripples.isEmpty else { return }
        let reach = hypot(bounds.width, bounds.height) * 0.6
        let ink = settings.levelColors ? Layer.Ink.error : Layer.Ink.plain
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age >= Self.rippleLife }
        for rp in ripples {
            let t = CGFloat(rp.age / Self.rippleLife)
            let radius = reach * (1 - (1 - t) * (1 - t))  // fast at first, slowing
            let strength = Float(1 - t) * 0.9
            for layer in layers {
                let band = layer.cellH * 1.5
                let r0 = max(0, Int((rp.y - radius - band) / layer.cellH)), r1 = min(layer.rows - 1, Int((rp.y + radius + band) / layer.cellH))
                guard r0 <= r1 else { continue }
                for r in r0...r1 {
                    let dy = (CGFloat(r) + 0.5) * layer.cellH - rp.y
                    let base = r * layer.cols
                    for c in 0..<layer.cols {
                        let dx = (CGFloat(c) + 0.5) * layer.cellW - rp.x
                        let off = abs(hypot(dx, dy) - radius)
                        guard off < band else { continue }
                        let b = strength * Float(1 - off / band)
                        let idx = base + c
                        guard b > layer.bright[idx] else { continue }
                        layer.bright[idx] = b
                        if layer.ink[idx] != Layer.Ink.keyword && layer.ink[idx] != Layer.Ink.keywordOnError {
                            layer.ink[idx] = ink
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error banner

    static let bannerGap: CFTimeInterval = 10  // at least this long between banners
    static let bannerWidth = 72                // columns at most
    static let bannerLines = 3                 // rows at most; the rest is cut

    private func stepBanner(_ dt: Float, _ front: Layer) {
        if settings.errorBanner, banner == nil, CACurrentMediaTime() - lastBanner >= Self.bannerGap,
           let text = layers.lazy.flatMap({ $0.newErrors }).first?.text {
            startBanner(text, front)
        }
        guard var b = banner else { return }
        b.age += dt
        if b.done || !settings.errorBanner {
            banner = nil
            bannerBox = nil
            return
        }
        let melting = b.melting
        bannerBox = melting > 0 ? nil : b.box
        if let box = bannerBox {
            // Clear the strip so the letters read; the rain carries on around it.
            for r in box.r0...box.r1 {
                for c in box.c0...box.c1 { front.bright[r * front.cols + c] = 0 }
            }
        }
        for i in 0..<b.shown where melting <= b.release[i] {
            let cell = b.cells[i]
            let idx = cell.r * front.cols + cell.c
            front.chars[idx] = cell.v & LogFeed.glyphBits
            front.ink[idx] = LogFeed.ink(cell.v, levels: true)
            front.bright[idx] = 1
        }
        banner = b
    }

    /// Lays the line out in the middle of the screen, wrapped at spaces, and starts writing it.
    private func startBanner(_ text: [UInt16], _ front: Layer) {
        let width = min(Self.bannerWidth, front.cols - 4)
        guard width >= 12, front.rows >= Self.bannerLines + 4, !text.isEmpty else { return }
        var lines: [ArraySlice<UInt16>] = []
        var i = 0
        while i < text.count, lines.count < Self.bannerLines {
            var end = min(i + width, text.count)
            if end < text.count,
               let space = text[(i + width / 2)..<end].lastIndex(where: { $0 & LogFeed.glyphBits == 0 }) {
                end = space + 1
            }
            lines.append(text[i..<end])
            i = end
            while i < text.count, text[i] & LogFeed.glyphBits == 0 { i += 1 }  // no leading spaces
        }
        let longest = lines.map(\.count).max() ?? 0
        let c0 = (front.cols - longest) / 2
        let r0 = Int.random(in: (front.rows / 5)...max(front.rows / 5, front.rows * 2 / 3 - lines.count))
        var cells: [(r: Int, c: Int, v: UInt16)] = []
        for (n, line) in lines.enumerated() {
            for (k, v) in line.enumerated() where v & LogFeed.glyphBits != 0 {
                cells.append((r0 + n, c0 + k, v))
            }
        }
        guard !cells.isEmpty else { return }
        let box = (c0: max(0, c0 - 1), c1: min(front.cols - 1, c0 + longest), r0: max(0, r0 - 1),
                   r1: min(front.rows - 1, r0 + lines.count))
        banner = Banner(cells: cells, box: box, release: cells.map { _ in Float.random(in: 0..<Banner.melt) })
        lastBanner = CACurrentMediaTime()
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
                front.ink[idx] = Layer.Ink.plain
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
                    front.ink[idx] = Layer.Ink.plain
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
            for layer in layers where !layer.inkGlyphs.isEmpty { drawInk(layer, ctx, isFront: layer === front) }
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

        // Darken the layers behind the banner too.
        if isFront, let box = bannerBox {
            ctx.setAlpha(1)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.85))
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
                var alpha = CGFloat(b * b) * layer.alpha
                if !layer.ink.isEmpty {
                    let ink = layer.ink[base + c]
                    if ink == Layer.Ink.debug {
                        alpha *= 0.4
                    } else if Layer.Ink.coloured(ink) && !layer.inkGlyphs.isEmpty {
                        continue  // drawn after tinting
                    }
                }
                ctx.setAlpha(alpha)
                ctx.draw(layer.trailGlyphs[Int(layer.chars[base + c])],
                         in: CGRect(x: CGFloat(c) * layer.cellW - layer.pad + dx, y: y, width: imgW, height: imgH))
            }
        }

        ctx.setAlpha(layer.alpha)
        forEachVisibleHead(layer, box: box) { idx, x, y in
            ctx.draw(layer.headGlyphs[idx], in: CGRect(x: x, y: y, width: imgW, height: imgH))
        }
    }

    /// Coloured cells in log mode (keywords, error and warning lines), skipped by drawLayer and drawn
    /// here after tinting so they keep their own colour. They fade like the rest of the trail.
    private func drawInk(_ layer: Layer, _ ctx: CGContext, isFront: Bool) {
        let imgW = layer.cellW + layer.pad * 2
        let imgH = layer.cellH + layer.pad * 2
        let box = settings.clock && isFront ? clockBox : nil
        for r in 0..<layer.rows {
            let y = bounds.height - CGFloat(r + 1) * layer.cellH - layer.pad
            let dx = glitchBands.isEmpty ? 0 : glitchShift(atY: y)
            let base = r * layer.cols
            for c in 0..<layer.cols where Layer.Ink.coloured(layer.ink[base + c]) {
                var b = layer.bright[base + c]
                if let box, r >= box.r0, r <= box.r1, c >= box.c0, c <= box.c1 {
                    b = clockMask[base + c] ? max(b, 0.95) : b * 0.3
                }
                if b < 0.02 { continue }
                // Brighter than the trail around it (which fades as b squared): red reads darker
                // than green, and keywords should stand out.
                ctx.setAlpha(CGFloat(min(1, b * 1.5)) * layer.alpha)
                let glyphs = layer.inkGlyphs[Int(layer.ink[base + c])]
                ctx.draw(glyphs[Int(layer.chars[base + c])],
                         in: CGRect(x: CGFloat(c) * layer.cellW - layer.pad + dx, y: y, width: imgW, height: imgH))
            }
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
        // A log drop has no head until it reaches the row its line starts at.
        for d in layer.drops where !d.idle && d.lastRow >= 0 && d.lastRow < layer.rows
            && (layer.feed == nil || d.lastRow >= d.startRow) {
            if let box, d.lastRow >= box.r0, d.lastRow <= box.r1, d.col >= box.c0, d.col <= box.c1 { continue }
            if layer === layers.last, let b = bannerBox,
               d.lastRow >= b.r0, d.lastRow <= b.r1, d.col >= b.c0, d.col <= b.c1 { continue }
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

extension OptionsController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? NSTextField) === lokiURLField { controlsChanged() }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === lokiQueryField { rebuildServicesMenu() }
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
    private var logSourcePopup: NSPopUpButton!
    private var logPathField: NSTextField!
    private var lokiURLField: NSTextField!
    private var lokiQueryField: NSTextField!
    private var servicesButton: NSPopUpButton!
    private var knownServices: [String] = []   // service_name values Loki has, once fetched
    private var servicesStatus = ""            // shown in the menu while there is no list
    private var fetchedURL = ""                // Loki address the list came (or is coming) from
    private var keywordsField: NSTextField!
    private var levelCheck: NSButton!
    private var volumeCheck: NSButton!
    private var rippleCheck: NSButton!
    private var bannerCheck: NSButton!
    private var logsNote: NSTextField!

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
            let page = FlippedView(frame: NSRect(x: 0, y: margin + rowH * 1.25, width: width, height: rowH * 11))
            content.addSubview(page)
            pages.append(page)
            parent = page
            originY = 0
        }

        let tabs = NSSegmentedControl(labels: ["Rain", "Effects", "Text", "Logs"], trackingMode: .selectOne,
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

        // Logs page.
        newPage()
        let wideW = controlW + valueW + gap
        label("Source:", row: 0)
        logSourcePopup = popup(["Log file", "Loki server"], row: 0)
        label("Log file:", row: 1)
        logPathField = textField(row: 1, x: controlX, width: wideW)
        logPathField.placeholderString = Settings.defaultLogPath
        label("Loki URL:", row: 2)
        lokiURLField = textField(row: 2, x: controlX, width: wideW)
        lokiURLField.placeholderString = "http://192.168.1.10:3100"
        lokiURLField.delegate = self  // refetch the services when the address is edited
        label("Services:", row: 3)
        servicesButton = NSPopUpButton(frame: .zero, pullsDown: true)
        servicesButton.addItem(withTitle: "")
        place(servicesButton, row: 3, x: controlX - 3, width: wideW + 6)
        label("Query:", row: 4)
        lokiQueryField = textField(row: 4, x: controlX, width: wideW)
        lokiQueryField.placeholderString = Settings.defaultLokiQuery
        lokiQueryField.delegate = self  // keep the service ticks in step with typed queries
        label("Keywords:", row: 5)
        keywordsField = textField(row: 5, x: controlX, width: wideW)
        keywordsField.placeholderString = "Shown in red; separate with commas"
        levelCheck = checkbox("Colour lines by log level", row: 6, x: controlX)
        volumeCheck = checkbox("More rain when logs are busy", row: 7, x: controlX)
        rippleCheck = checkbox("Ripple when an error arrives", row: 8, x: controlX)
        bannerCheck = checkbox("Write new errors across the screen", row: 9, x: controlX)
        logsNote = NSTextField(wrappingLabelWithString: "")
        logsNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        logsNote.textColor = .secondaryLabelColor
        logsNote.frame = NSRect(x: controlX, y: 10 * rowH + 2, width: wideW, height: rowH * 1.5)
        parent.addSubview(logsNote)

        for page in pages.dropFirst() { page.isHidden = true }
        parent = content
        originY = margin

        // Credit line. Bundle.main is the host process here, so look up the saver's own bundle.
        let creditRow: CGFloat = 12.35
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
        logSourcePopup.selectItem(at: s.logSource)
        logPathField.stringValue = s.logPath
        lokiURLField.stringValue = s.lokiURL
        lokiQueryField.stringValue = s.lokiQuery
        rebuildServicesMenu()
        keywordsField.stringValue = s.keywords
        levelCheck.state = s.levelColors ? .on : .off
        volumeCheck.state = s.followVolume ? .on : .off
        rippleCheck.state = s.errorRipple ? .on : .off
        bannerCheck.state = s.errorBanner ? .on : .off
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
        let logs = charset == Settings.logCharset
        let loki = logSourcePopup.indexOfSelectedItem == 1
        logSourcePopup.isEnabled = logs
        logPathField.isEnabled = logs && !loki
        lokiURLField.isEnabled = logs && loki
        lokiQueryField.isEnabled = logs && loki
        servicesButton.isEnabled = logs && loki
        if logs && loki { fetchServices() }
        keywordsField.isEnabled = logs
        levelCheck.isEnabled = logs
        volumeCheck.isEnabled = logs
        rippleCheck.isEnabled = logs
        bannerCheck.isEnabled = logs
        logsNote.stringValue = logs
            ? (loki ? "Tick services, or type any LogQL query. Shows its last day of lines, then new ones as they arrive."
                    : "Shows the end of the file, then new lines as they are written.")
            : "Choose Logs under Characters on the Rain tab to use these."

        // Show the preset these values match, or Custom when they match none.
        let close: (Double, Double) -> Bool = { abs($0 - $1) < 0.005 }
        let match = Settings.presets.firstIndex {
            close($0.speed, speedSlider.doubleValue) && close($0.density, densitySlider.doubleValue)
                && close($0.size, sizeSlider.doubleValue) && close($0.glow, glowSlider.doubleValue)
        }
        presetPopup.selectItem(at: match.map { $0 + 1 } ?? 0)
    }

    // MARK: Loki services

    // A query that is just a list of services: {service_name="a"} or {service_name=~"a|b"}.
    // container_name is read too, as earlier versions used it.
    private static let servicesQuery = try! NSRegularExpression(
        pattern: #"^\s*\{\s*(service_name|container_name)\s*=~?\s*"([^"|]+(\|[^"|]+)*)"\s*\}\s*$"#)

    /// The services the query names, or nil when it is some other query.
    private func selectedServices() -> [String]? {
        var q = lokiQueryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { q = Settings.defaultLokiQuery }
        guard let m = Self.servicesQuery.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let r = Range(m.range(at: 2), in: q) else { return nil }
        return q[r].split(separator: "|").map(String.init)
    }

    private func servicesTitle(_ selected: [String]?) -> String {
        guard let selected else { return "Custom query" }
        return selected.joined(separator: ", ")
    }

    /// One checkbox per service. They sit in menu items as views, so ticking one leaves the menu
    /// open for the next. Services in the query but not on the server are listed too.
    private func rebuildServicesMenu() {
        let selected = selectedServices()
        let menu = NSMenu()
        menu.addItem(withTitle: servicesTitle(selected), action: nil, keyEquivalent: "")  // a pull-down's title
        let names = Set(knownServices + (selected ?? [])).sorted()
        if knownServices.isEmpty, !servicesStatus.isEmpty {
            let status = menu.addItem(withTitle: servicesStatus, action: nil, keyEquivalent: "")
            status.isEnabled = false
        }
        for name in names {
            let box = NSButton(checkboxWithTitle: name, target: self, action: #selector(serviceToggled(_:)))
            box.state = selected?.contains(name) == true ? .on : .off
            box.sizeToFit()
            box.frame.origin = NSPoint(x: 14, y: 3)
            let holder = NSView(frame: NSRect(x: 0, y: 0, width: max(240, box.frame.maxX + 14), height: box.frame.height + 6))
            holder.addSubview(box)
            let item = NSMenuItem()
            item.view = holder
            menu.addItem(item)
        }
        servicesButton.menu = menu
    }

    @objc private func serviceToggled(_ sender: NSButton) {
        guard let menu = servicesButton.menu else { return }
        let chosen = menu.items.compactMap { $0.view?.subviews.first as? NSButton }.filter { $0.state == .on }.map(\.title)
        if chosen.isEmpty {  // the rain needs at least one
            sender.state = .on
            return
        }
        lokiQueryField.stringValue = chosen.count == 1
            ? #"{service_name=""# + chosen[0] + #""}"#
            : #"{service_name=~""# + chosen.joined(separator: "|") + #""}"#
        menu.items.first?.title = servicesTitle(chosen)
    }

    /// Asks Loki for its service names, once per address. Covers the last week, so quiet services
    /// (Loki's default is six hours) are still listed.
    private func fetchServices() {
        var root = lokiURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard root != fetchedURL else { return }
        fetchedURL = root
        knownServices = []
        guard !root.isEmpty, var c = URLComponents(string: root + "/loki/api/v1/label/service_name/values"),
              c.host != nil, ["http", "https"].contains(c.scheme?.lowercased() ?? "") else {
            servicesStatus = "Enter the Loki URL to list services"
            rebuildServicesMenu()
            return
        }
        let now = Date().timeIntervalSince1970
        c.queryItems = [URLQueryItem(name: "start", value: String(UInt64((now - 7 * 86400) * 1e9))),
                        URLQueryItem(name: "end", value: String(UInt64(now * 1e9)))]
        servicesStatus = "Loading services…"
        rebuildServicesMenu()
        guard let url = c.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let names = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["data"] as? [String]
            DispatchQueue.main.async {
                guard let self, self.fetchedURL == root else { return }  // the address changed meanwhile
                if let names {
                    self.knownServices = names.sorted()
                    if names.isEmpty { self.servicesStatus = "No services in the last 7 days" }
                } else {
                    self.servicesStatus = "Can't reach Loki at \(root)"
                    self.fetchedURL = ""  // try again next time
                }
                self.rebuildServicesMenu()
            }
        }.resume()
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
        s.logPath = logPathField.stringValue
        s.logSource = logSourcePopup.indexOfSelectedItem
        s.lokiURL = lokiURLField.stringValue
        s.lokiQuery = lokiQueryField.stringValue
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
        s.keywords = keywordsField.stringValue
        s.levelColors = levelCheck.state == .on
        s.followVolume = volumeCheck.state == .on
        s.errorRipple = rippleCheck.state == .on
        s.errorBanner = bannerCheck.state == .on
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
