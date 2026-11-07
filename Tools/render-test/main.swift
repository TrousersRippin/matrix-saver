// Render test for MatrixView, run by Tools/render-test.sh. Runs the saver outside System Settings
// in Logs mode, saves a frame as a PNG, and optionally a tab of the Options sheet, or drives the
// Loki Services menu and prints what happens.
//
// Not sandboxed, unlike the real host (legacyScreenSaver), so it can't prove sandbox behaviour.
// Its settings go to the unsandboxed ByHost prefs, not the real saver's; the script deletes them.
import AppKit
import ScreenSaver

let env = ProcessInfo.processInfo.environment
let source = env["SOURCE"] ?? "/var/log/install.log"   // a log file, or a Loki URL
let out = env["OUT"] ?? "build/render-test.png"
let seconds = Double(env["DURATION"] ?? "8") ?? 8

let d = ScreenSaverDefaults(forModuleWithName: "local.agentsmith.MatrixSaver")!
d.set(4, forKey: "charset")  // Logs
if source.hasPrefix("http://") || source.hasPrefix("https://") {
    d.set(1, forKey: "logSource")
    d.set(source, forKey: "lokiURL")
    if let q = env["QUERY"] { d.set(q, forKey: "lokiQuery") }
} else {
    d.set(0, forKey: "logSource")
    d.set(source, forKey: "logPath")
}
d.set(false, forKey: "intro")
d.set(false, forKey: "glitches")
d.set(false, forKey: "messages")
d.set(false, forKey: "depth")
d.set(Int(env["COLOR"] ?? "0") ?? 0, forKey: "colorIndex")  // 4 = Red
d.synchronize()

let v = MatrixView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), isPreview: false)!
let scratch = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
v.cacheDisplay(in: v.bounds, to: scratch)  // the first draw lays the view out
v.startAnimation()
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    v.animateOneFrame()
    v.cacheDisplay(in: v.bounds, to: scratch)
    // Run the main run loop, not usleep: Loki replies are delivered on the main queue.
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
v.cacheDisplay(in: v.bounds, to: rep)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)

func all<T: NSView>(_ t: T.Type, in view: NSView) -> [T] {
    view.subviews.flatMap { [$0 as? T].compactMap { $0 } + all(t, in: $0) }
}

// SHEET=<png> TAB=<0-3>: the Options sheet on a tab (0 Rain, 1 Effects, 2 Text, 3 Logs).
// Light mode, as dark-mode labels come out white on a transparent PNG.
if let sheetOut = env["SHEET"] {
    let w = v.configureSheet!
    w.appearance = NSAppearance(named: .aqua)
    let tabs = all(NSSegmentedControl.self, in: w.contentView!).first!
    tabs.selectedSegment = Int(env["TAB"] ?? "0") ?? 0
    _ = tabs.sendAction(tabs.action, to: tabs.target)
    RunLoop.main.run(until: Date().addingTimeInterval(3))  // let a Loki service list arrive
    let cv = w.contentView!
    let r = cv.bitmapImageRepForCachingDisplay(in: cv.bounds)!
    cv.cacheDisplay(in: cv.bounds, to: r)
    try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: sheetOut))
    print("wrote", sheetOut)
}

// MENU=1 (with a Loki SOURCE): drives the Services menu and prints the query it writes.
if env["MENU"] != nil {
    let w = v.configureSheet!
    RunLoop.main.run(until: Date().addingTimeInterval(6))  // let the service list arrive
    let pull = all(NSPopUpButton.self, in: w.contentView!).first { $0.pullsDown }!
    let query = all(NSTextField.self, in: w.contentView!).first { $0.isEditable && $0.placeholderString?.contains("service_name") == true }!
    let boxes = pull.menu!.items.compactMap { $0.view?.subviews.first as? NSButton }
    print("title:", pull.menu!.items[0].title, "| enabled:", pull.isEnabled)
    print("services:", boxes.count, boxes.map { $0.state == .on ? "[x]\($0.title)" : $0.title }.joined(separator: " "))
    if let first = boxes.first(where: { $0.state == .off }) {
        first.performClick(nil)
        print("after ticking \(first.title):", query.stringValue)
    }
    query.stringValue = #"{service_name="traefik"} |= "500""#
    NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: query)
    print("typed a custom query -> title:", pull.menu!.items[0].title)
}
