
// MARK: - Feed tests (appended to a copy of MatrixView.swift by Tools/feed-test.sh)
//
// Everything that touches LogFeed's private members lives in an extension of LogFeed, which Swift
// allows because the extension ends up in the same file.

import Foundation

private var failures = 0
private var checks = 0
private var group = ""

private func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if ok {
        print("  ok    \(name)")
    } else {
        failures += 1
        let d = detail()
        print("  FAIL  \(name)\(d.isEmpty ? "" : ": \(d)")")
    }
}

private func expectEqual<T: Equatable>(_ got: T, _ want: T, _ name: String) {
    check(got == want, name, "got \(got), want \(want)")
}

/// Runs the main run loop until `done` or `timeout` seconds; Loki replies arrive on the main queue.
@discardableResult
private func wait(_ timeout: Double = 5, until done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return done()
}

/// Words with no hex letters or digits, so lines built from them never fold into one another.
private func word(_ i: Int) -> String {
    let letters = Array("ghijklmnopqrstuvwxyz")
    var n = i, s = ""
    repeat { s.append(letters[n % letters.count]); n /= letters.count } while n > 0
    return s
}

func runFeedTests(scratch: String) -> Bool {
    try? FileManager.default.removeItem(atPath: scratch)
    try! FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    URLProtocol.registerClass(FakeLoki.self)
    let filter = ProcessInfo.processInfo.environment["FILTER"]?.lowercased()
    let groups: [(String, () -> Void)] = [
        ("cleanup", LogFeed.testCleanup),
        ("levels", LogFeed.testLevels),
        ("keywords", LogFeed.testKeywords),
        ("shape", LogFeed.testShape),
        ("fair share", LogFeed.testFairShare),
        ("volume", LogFeed.testVolume),
        ("file", { LogFeed.testFile(scratch) }),
        ("loki", LogFeed.testLoki),
        ("loki start rounds", LogFeed.testLokiRounds),
        ("quiet rules", LogFeed.testQuietRules),
    ]
    for (name, run) in groups where filter == nil || name.contains(filter!) {
        group = name
        print(name)
        run()
    }
    print(failures == 0 ? "\nall \(checks) checks passed" : "\n\(failures) of \(checks) checks FAILED")
    return failures == 0
}

// MARK: Fake Loki

/// Answers requests to http://fake-loki.test with `handler`'s status and JSON body.
final class FakeLoki: URLProtocol {
    static var handler: ((URLComponents) -> (Int, Any))?
    static var requests: [URLComponents] = []

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fake-loki.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        DispatchQueue.main.sync { FakeLoki.requests.append(c) }
        var answer: (Int, Any) = (500, ["error": "no handler"])
        DispatchQueue.main.sync { if let h = FakeLoki.handler { answer = h(c) } }
        let data = try! JSONSerialization.data(withJSONObject: answer.1)
        let response = HTTPURLResponse(url: url, statusCode: answer.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func param(_ c: URLComponents, _ name: String) -> String {
        c.queryItems?.first { $0.name == name }?.value ?? ""
    }

    /// A query_range reply of log streams: each stream's labels and (nanosecond time, line) pairs.
    static func streams(_ s: [([String: String], [(UInt64, String)])]) -> Any {
        ["status": "success", "data": ["resultType": "streams", "result": s.map { labels, values in
            ["stream": labels, "values": values.map { [String($0.0), $0.1] }] as [String: Any]
        }]]
    }

    /// A query_range reply of metric series: each service's (seconds, count) points.
    static func matrix(_ s: [String: [(Double, Double)]]) -> Any {
        ["status": "success", "data": ["resultType": "matrix", "result": s.map { name, points in
            ["metric": ["service_name": name], "values": points.map { [$0.0, String(Int($0.1))] }] as [String: Any]
        }]]
    }
}

extension LogFeed {
    static func text(_ glyphs: [UInt16]) -> String {
        String(String.UnicodeScalarView(glyphs.map { Unicode.Scalar(UInt32($0 & glyphBits) + 0x20)! }))
    }

    private var alertTexts: [String] { alerts.map { Self.text($0.text) } }
    private func lines(_ key: String) -> [String] {
        sourceIndex[key].map { sources[$0].lines.map(Self.text) } ?? []
    }

    // MARK: Cleanup

    static func testCleanup() {
        expectEqual(stripTimestamp("2026-11-06 10:22:01+01 macbook-pro Safari[53369]: hi"), "Safari[53369]: hi",
                    "ISO time and host name stripped")
        expectEqual(stripTimestamp("2026-11-06T10:22:01Z INF hi"), "INF hi", "zerolog level kept after ISO time")
        expectEqual(stripTimestamp("2026-11-06 11:24:51.319 CET started"), "started", "time zone name stripped")
        expectEqual(stripTimestamp("Fri Nov  6 10:28:56.515 x"), "x", "syslog time stripped")
        expectEqual(stripANSI("[\u{1B}[32minfo\u{1B}[39m] ok"), "[info] ok", "ANSI colour codes removed")
        expectEqual(tidy(#"{"level":"error","msg":"boom","code":7,"ts":"2026-11-06T10:00:00Z"}"#), "error boom code=7",
                    "JSON becomes level message key=value")
        expectEqual(tidy(#"ts=2026-11-06 caller=x.go:12 level=info msg="hi there" org_id=fake"#),
                    #"level=info msg="hi there""#, "logfmt noise dropped")
        expectEqual(tidy("UCG-Fiber UCG-Fiber kernel: x"), "UCG-Fiber kernel: x", "repeated host name dropped")
        expectEqual(duration(40), "40 s", "duration in seconds")
        expectEqual(duration(18 * 60), "18 min", "duration in minutes")
        expectEqual(duration(2 * 3600), "2 h", "duration in whole hours")
        expectEqual(duration(2 * 3600 + 5 * 60), "2 h 5 min", "duration in hours and minutes")
        expectEqual(query(#"{service_name=~"a|b"} |= "x""#, excluding: ["busy", "loud"]),
                    #"{service_name!~"busy|loud", service_name=~"a|b"} |= "x""#, "services excluded from a query")
    }

    // MARK: Levels

    static func testLevels() {
        let cases: [(String, Level)] = [
            ("level=error something broke", .error),
            ("lvl: warn disk at 80%", .warn),
            ("E1114 10:00:00.123456 server.go:1] failed", .error),
            ("CEF:0|Ubiquiti|UniFi|1.0|201|Threat|8|act=blocked", .error),
            ("CEF:0|Ubiquiti|UniFi|1.0|201|Threat|5|act=blocked", .warn),
            ("[warn] disk nearly full", .warn),
            ("WRN lease was lost", .warn),
            ("debug: cache hit", .debug),
            ("postgres: ERROR: relation does not exist", .error),
            ("an error occurred while saving", .normal),  // lower case, not first: a mention
            ("errors=0 all fine", .normal),
            ("INF started", .normal),
        ]
        for (line, want) in cases { expectEqual(level(of: line), want, "level of \"\(line)\"") }
        expectEqual(level(labels: ["detected_level": "error"]), .error, "level from detected_level label")
        expectEqual(level(labels: ["severity": "8"]), .error, "level from CEF severity label")
        expectEqual(level(labels: ["detected_level": "unknown"]), nil, "unknown level label ignored")
    }

    // MARK: Keywords

    static func testKeywords() {
        let f = LogFeed(source: .file("/nonexistent/feed-test"), keywords: ["error"], levels: true)
        let g = f.encode("An ERROR here", level: .error)
        let marked = g.indices.filter { g[$0] & keywordBit != 0 }
        expectEqual(marked, Array(3..<8), "keyword letters marked, any case")
        expectEqual(level(of: g), .error, "level carried in the glyph bits")
        expectEqual(ink(g[0], levels: true), Layer.Ink.error, "error ink with level colours")
        expectEqual(ink(g[0], levels: false), Layer.Ink.plain, "plain ink without level colours")
        expectEqual(ink(g[3], levels: true), Layer.Ink.keywordOnError, "keyword on an error line")
    }

    // MARK: Shape

    static func testShape() {
        let f = LogFeed(source: .file("/nonexistent/feed-test"), keywords: [], levels: true)
        func shape(_ s: String) -> Int { Self.shape(of: f.encode(s, level: .normal)) }
        check(shape("DROP SRC=10.1.1.11 MAC=a4:cc:5e:01 LEN=60") == shape("DROP SRC=9.9.9.9 MAC=ff:00:12:ab LEN=1500"),
              "IPs, MACs and numbers fold")
        check(shape("job took 12:04:31") == shape("job took 1:00:00"), "times fold")
        check(shape(#"msg="done" a=1 b=2"#) == shape(#"b=7 msg="done" a=3"#), "word order doesn't matter")
        check(shape("cache added cafe") != shape("cache added beef"), "hex-looking words without digits stay")
        check(shape("disk sda full") != shape("disk sda empty"), "different words differ")
        // Long lines differing only in number widths: shaped before the cut, so they fold.
        let pad = String(repeating: "word ", count: 60)
        let long1 = "SRC=1.2.3.4 " + pad + "LEN=1"
        let long2 = "SRC=111.222.233.244 " + pad + "LEN=12345"
        f.clearSources()
        f.store([f.encode(long1, level: .normal), f.encode(long2, level: .normal)], in: "k")
        expectEqual(f.lines("k").count, 1, "long repeats fold despite the cut")
        expectEqual(f.lines("k").first?.count ?? 0 <= maxLineLength, true, "kept line is cut to maxLineLength")
        check(f.lines("k").first?.hasPrefix("SRC=111.") == true, "the newest of a shape is kept")
        f.store([f.encode("other line", level: .normal), f.encode("SRC=5.5.5.5 " + pad + "LEN=3", level: .normal)], in: "k")
        expectEqual(f.lines("k").count, 2, "a repeat replaces the older line")
        check(f.lines("k").last?.hasPrefix("SRC=5.5.5.5") == true, "and moves to the newest end")
    }

    // MARK: Fair share

    static func testFairShare() {
        let f = LogFeed(source: .file("/nonexistent/feed-test"), keywords: [], levels: true)
        f.clearSources()
        for (key, n) in [("big", 300), ("small", 10), ("tiny", 2)] {
            f.store((0..<n).map { f.encode("\(key) \(word($0))", level: .normal) }, in: key)
        }
        var counts: [String: Int] = [:]
        let total = 3000
        for _ in 0..<total {
            let t = text(f.nextLine().text)
            counts[String(t.prefix { $0 != " " }), default: 0] += 1
        }
        // Weights sqrt(300) : sqrt(10) : sqrt(2) = 79% : 14.5% : 6.5%.
        let share = { (k: String) in Double(counts[k, default: 0]) / Double(total) }
        check(abs(share("big") - 0.79) < 0.02, "busy source gets ~79%", "\(share("big"))")
        check(abs(share("small") - 0.145) < 0.02, "small source gets ~14.5%", "\(share("small"))")
        check(abs(share("tiny") - 0.065) < 0.02, "tiny source gets ~6.5%", "\(share("tiny"))")
        f.append([("tiny", f.encode("tiny brand new", level: .normal))])
        let next = f.nextLine()
        check(next.isNew && text(next.text) == "tiny brand new", "new lines come first, marked new")
    }

    // MARK: Volume

    static func testVolume() {
        let f = LogFeed(source: .file("/nonexistent/feed-test"), keywords: [], levels: true)
        f.clearSources()
        let now = CACurrentMediaTime()
        f.baseline = 1
        f.lastVolume = now - 1
        f.arrivals = [(now, 100)]  // 5 lines/s over the 20 s window: 5× usual
        f.updateVolume(now)
        check((2.2...2.25).contains(f.volume), "5× usual gives volume ~sqrt(5)", "\(f.volume)")
        expectEqual(f.baseline! < 1.01, true, "a burst moves the usual rate only slowly")
        f.arrivals = []
        f.lastVolume = now
        f.updateVolume(now + 1)
        expectEqual(f.volume, volumeRange.lowerBound, "silence gives the lowest volume")
    }

    // MARK: File

    static func testFile(_ dir: String) {
        let path = dir + "/test.log"
        func write(_ lines: [String], append: Bool = true) {
            let data = Data(lines.map { $0 + "\n" }.joined().utf8)
            if append, let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
        let first = (0..<10).map { "first \(word($0))" }
        write(first, append: false)
        let f = LogFeed(source: .file(path), keywords: [], levels: true)
        expectEqual(f.lines(""), first, "start: the file's lines")
        expectEqual(f.nextLine().isNew, false, "start lines aren't new")

        write(["second one", "second two", "second three"])
        f.pollFile(path)
        expectEqual(f.fresh.map(text), ["second one", "second two", "second three"], "appended lines are new")
        f.fresh = []

        // More than tailBytes appended at once: read from the first whole line in the last 256 KB.
        let pad = String(repeating: "z", count: 80)
        let big = (0..<4000).map { "line \(word($0)) \(pad) end" }
        write(big)
        f.pollFile(path)
        let all = f.lines("")
        let bigKept = all.filter { !$0.hasPrefix("first ") && !$0.hasPrefix("second ") }
        check(bigKept.allSatisfy { $0.hasPrefix("line ") && $0.hasSuffix(" end") }, "big append: no partial lines",
              bigKept.first { !($0.hasPrefix("line ") && $0.hasSuffix(" end")) } ?? "")
        check(bigKept.count > 2500 && bigKept.last == big.last, "big append: the last 256 KB kept", "\(bigKept.count)")
        check(all.contains(first[0]), "big append: earlier history kept")
        f.fresh = []

        // Rename-and-create rotation to a smaller file.
        let before = f.lines("").count
        try! FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        write(["rotated one", "rotated two"], append: false)
        f.pollFile(path)
        expectEqual(f.fresh.map(text), ["rotated one", "rotated two"], "rotation: the new file's lines are new")
        expectEqual(f.lines("").count, before + 2, "rotation: history kept")
        f.fresh = []

        // Rotation to a new file bigger than the old offset: noticed by its inode, read from its start.
        try! FileManager.default.removeItem(atPath: path + ".1")
        try! FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        let third = (0..<5).map { "third file \(word($0)) with a longer line" }
        write(third, append: false)
        f.pollFile(path)
        expectEqual(f.fresh.map(text), third, "rotation to a bigger file: all its lines, from the start")
        f.fresh = []

        // Copy-and-truncate.
        write(["truncated"], append: false)  // same inode, shorter
        f.pollFile(path)
        expectEqual(f.fresh.map(text), ["truncated"], "copy-truncate: the file is read from its start")

        // Repeats fold when the file is loaded.
        let foldPath = dir + "/fold.log"
        let repeats = (0..<200).map { "gw kernel: DROP SRC=\($0 % 250).2.3.4 MAC=a4:\($0 % 90 + 10):5e DST=10.1.1.11 LEN=\($0 * 7)" }
        FileManager.default.createFile(atPath: foldPath, contents: Data((repeats + ["hello world"]).map { $0 + "\n" }.joined().utf8))
        let g = LogFeed(source: .file(foldPath), keywords: [], levels: true)
        expectEqual(g.lines("").count, 2, "200 repeats and one other line keep 2")

        let empty = dir + "/empty.log"
        FileManager.default.createFile(atPath: empty, contents: Data())
        let e = LogFeed(source: .file(empty), keywords: [], levels: true)
        expectEqual(text(e.nextLine().text), "\(empty) IS EMPTY", "empty file says so")
        let m = LogFeed(source: .file(dir + "/missing.log"), keywords: [], levels: true)
        expectEqual(text(m.nextLine().text), "CANNOT READ \(dir)/missing.log", "missing file says so")
    }

    // MARK: Loki

    static func testLoki() {
        let base = "http://fake-loki.test"
        let t0 = UInt64(Date().timeIntervalSince1970) * 1_000_000_000
        let s: UInt64 = 1_000_000_000
        let pg = ["service_name": "pg", "container_name": "postgres"]
        let web = ["service_name": "web", "detected_level": "warn"]
        FakeLoki.requests = []
        FakeLoki.handler = { _ in
            (200, FakeLoki.streams([
                (pg, [(t0 - 100 * s, "LOG: checkpoint starting"), (t0 - 50 * s, "ERROR: relation does not exist")]),
                (web, [(t0 - 5 * s, #"{"level":"warn","msg":"slow request","path":"/a"}"#), (t0, "hello from web")]),
            ]))
        }
        let f = LogFeed(source: .loki(url: base, query: #"{service_name=~"pg|web"}"#), keywords: [], levels: true)
        check(wait { f.lokiOK }, "start fetch answered")
        let start = FakeLoki.requests.first
        check(start.map { FakeLoki.param($0, "query").hasSuffix(lokiFilters) } == true, "self-echo filters in the query")
        expectEqual(start.map { FakeLoki.param($0, "direction") }, "backward", "start fetch: newest first")
        expectEqual(f.lines("pg"), ["postgres: LOG: checkpoint starting", "postgres: ERROR: relation does not exist"],
                    "lines kept per service, named by container")
        expectEqual(f.lines("web").first, "web: warn slow request path=/a", "JSON line tidied, named by service")
        let pgError = f.sources[f.sourceIndex["pg"]!].lines[1]
        expectEqual(level(of: pgError), .error, "level from the line")
        expectEqual(level(of: f.sources[f.sourceIndex["web"]!].lines[1]), .warn, "level from the stream label")

        // A poll: one repeat from the overlap, one late line older than the newest, one new.
        let poll = FakeLoki.streams([
            (pg, [(t0 - 10 * s, "late arrival")]),
            (web, [(t0, "hello from web"), (t0 + 1 * s, "brand new")]),
        ])
        FakeLoki.requests = []
        FakeLoki.handler = { _ in (200, poll) }
        f.fetchLoki()
        check(wait { !f.lokiBusy }, "poll answered")
        let p = FakeLoki.requests.first
        expectEqual(p.map { FakeLoki.param($0, "direction") }, "forward", "poll: oldest first")
        expectEqual(p.map { FakeLoki.param($0, "start") }, String(t0 - lokiOverlap), "poll starts 30 s before the newest")
        expectEqual(f.fresh.map(text), ["postgres: late arrival", "web: brand new"], "late line caught, repeat skipped")
        f.fresh = []
        f.fetchLoki()
        wait { !f.lokiBusy }
        expectEqual(f.fresh.count, 0, "the same reply again adds nothing")

        // Quiet alerts: pg was steady and has logged nothing for 20 minutes.
        FakeLoki.requests = []
        FakeLoki.handler = { c in
            let end = Double(FakeLoki.param(c, "end"))!, from = Double(FakeLoki.param(c, "start"))!
            let steps = stride(from: from, through: end, by: 300).map { $0 }
            return (200, FakeLoki.matrix([
                "pg": steps.map { ($0, $0 <= end - 20 * 60 ? 4 : 0) },
                "web": steps.map { ($0, 9) },
            ]))
        }
        f.checkQuiet()
        check(wait { !f.quietBusy }, "quiet check answered")
        let metric = FakeLoki.requests.first.map { FakeLoki.param($0, "query") } ?? ""
        expectEqual(metric, #"sum by (service_name) (count_over_time({service_name=~"pg|web"}"# + lokiFilters + " [300s]))",
                    "quiet check: per-service counts of the query")
        expectEqual(f.alertTexts, ["pg has gone quiet: no lines for 20 min"], "steady service gone quiet")
        expectEqual(f.alerts.last.map { level(of: $0.text) }, .warn, "quiet alert is amber")
        f.checkQuiet()
        wait { !f.quietBusy }
        expectEqual(f.alerts.count, 1, "reported once")

        FakeLoki.handler = { _ in (200, FakeLoki.streams([(pg, [(t0 + 60 * s, "back again")])])) }
        f.fetchLoki()
        wait { !f.lokiBusy }
        check(f.alertTexts.last?.hasPrefix("pg is logging again after 2") == true, "a new line ends the silence",
              f.alertTexts.last ?? "")

        // Loki unreachable: reported after 30 s, once; then back.
        FakeLoki.handler = { _ in (500, ["error": "down"]) }
        let n = f.alerts.count
        f.fetchLoki()
        wait { !f.lokiBusy }
        expectEqual(f.alerts.count, n, "a single failure isn't reported")
        f.lokiDownSince = CACurrentMediaTime() - 31
        f.fetchLoki()
        wait { !f.lokiBusy }
        check(f.alertTexts.last?.hasPrefix("cannot reach Loki at \(base): HTTP 500") == true, "down 30 s is reported",
              f.alertTexts.last ?? "")
        expectEqual(f.alerts.last.map { level(of: $0.text) }, .error, "down alert is red")
        f.fetchLoki()
        wait { !f.lokiBusy }
        expectEqual(f.alerts.count, n + 1, "down is reported once")
        expectEqual(f.lines("pg").last, "postgres: back again", "history kept while Loki is down")
        FakeLoki.handler = { _ in (200, FakeLoki.streams([])) }
        f.fetchLoki()
        wait { !f.lokiBusy }
        expectEqual(f.alertTexts.last, "Loki is back after 31 s", "back is reported")
        check(f.quietGrace > CACurrentMediaTime(), "quiet alerts wait while Loki catches up")

        // Unreachable from the start: a status line instead of log lines.
        FakeLoki.handler = { _ in (500, ["error": "down"]) }
        let down = LogFeed(source: .loki(url: base, query: #"{job="x"}"#), keywords: [], levels: true)
        wait { !down.lokiBusy && FakeLoki.requests.count > 0 }
        wait(1) { false }
        check(text(down.nextLine().text).hasPrefix("CANNOT REACH \(base): HTTP 500"), "unreachable at start says so",
              text(down.nextLine().text))
        expectEqual(down.alerts.count, 0, "no alert before Loki has ever answered")
    }

    /// The start fetch in rounds: a service that fills the first round is left out of the next.
    static func testLokiRounds() {
        let t0 = UInt64(Date().timeIntervalSince1970) * 1_000_000_000
        FakeLoki.requests = []
        FakeLoki.handler = { c in
            let q = FakeLoki.param(c, "query")
            if q.contains(#"service_name!~"busy""#) {
                return (200, FakeLoki.streams([(["service_name": "calm"], [(t0 - 7_200_000_000_000, "calm line")])]))
            }
            let lines = (0..<UInt64(lokiStartLimit)).map { (t0 - $0 * 1_000_000_000, "busy \(word(Int($0)))") }
            return (200, FakeLoki.streams([(["service_name": "busy"], lines)]))
        }
        let f = LogFeed(source: .loki(url: "http://fake-loki.test", query: #"{service_name=~".+"}"#), keywords: [], levels: true)
        check(wait { f.sourceIndex["calm"] != nil }, "second round fetched the quieter service")
        expectEqual(FakeLoki.requests.count, 2, "two rounds")
        expectEqual(f.lines("busy").count, serviceHistory, "the busy service keeps serviceHistory lines")
    }

    // MARK: Quiet rules

    static func testQuietRules() {
        let f = LogFeed(source: .file("/nonexistent/feed-test"), keywords: [], levels: true)
        let now = Date().timeIntervalSince1970
        let from = now - 12 * 3600
        func series(_ n: (Double) -> Double) -> [(t: Double, n: Double)] {
            stride(from: from, through: now, by: 300).map { ($0, n($0)) }
        }
        func gappy(quiet minutes: Double) -> [(t: Double, n: Double)] {
            // Steady but skips two buckets in twenty (10-minute pauses): needs 30 min of silence.
            series { t in let k = Int((t - from) / 300); return t > now - minutes * 60 || k % 20 < 2 ? 0 : 3 }
        }
        f.evaluateQuiet([
            "steady-live": series { _ in 5 },
            "steady-quiet": series { $0 <= now - 20 * 60 ? 5 : 0 },
            "bursty": series { Int(($0 - from) / 300) % 6 == 0 ? 40 : 0 },
            "gappy": gappy(quiet: 20),
            "long-gone": series { $0 <= now - 7 * 3600 ? 5 : 0 },
            "new": series { $0 >= now - 2 * 3600 && $0 <= now - 30 * 60 ? 5 : 0 },
            "short-quiet": series { $0 <= now - 10 * 60 ? 5 : 0 },
        ], now: now)
        expectEqual(f.alertTexts, ["steady-quiet has gone quiet: no lines for 20 min"],
                    "only the steady service quiet for 15+ min (not live, bursty, pausing, gone >6 h, new, 10 min)")
        f.evaluateQuiet(["gappy": gappy(quiet: 35)], now: now)
        expectEqual(f.alertTexts.last, "gappy has gone quiet: no lines for 35 min", "a service that pauses: after 2× its longest gap")
        f.evaluateQuiet(["gappy": series { _ in 3 }], now: now)
        expectEqual(f.alertTexts.last, "gappy is logging again after 35 min", "counts show it back")
        f.quietGrace = CACurrentMediaTime() + 60
        let n = f.alerts.count
        f.evaluateQuiet(["other": series { $0 <= now - 20 * 60 ? 5 : 0 }], now: now)
        expectEqual(f.alerts.count, n, "no quiet alerts during the grace after Loki was down")
    }
}
