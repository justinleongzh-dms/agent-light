// Agent Light: a small traffic light in the corner of the screen that shows what Claude is doing.
// hook.py keeps one file per Claude session in sessions/; this app combines them into one light.
//   red    = a session stopped and needs me (a question, a permission, an approval). Flashes.
//   yellow = a session is working. Pulses slowly.
//   green  = nothing needs me. Steady.
// If any session needs me the light is red, even if others are working.
// When everything finishes, green flashes for at least 10 seconds, and keeps flashing until I switch back to Claude.
// Drag the light to move it. Right-click it to change its size or quit.

import Cocoa

let sessionsFolder = NSString(string: "~/.claude/agent-light/sessions").expandingTildeInPath
let claudeAppID = "com.anthropic.claudefordesktop"
let minimumFlashSeconds = 10.0

let sizes: [(name: String, scale: CGFloat)] = [
    ("Small", 0.75),
    ("Medium", 1.0),
    ("Large", 1.5),
    ("Extra large", 2.0),
]

// The size I picked last time (Medium if never picked)
var scale = CGFloat(UserDefaults.standard.double(forKey: "scale"))
if scale == 0 {
    scale = 1.0
}

func lightSize() -> NSSize {
    let lampSize = 18 * scale
    let gap = 5 * scale
    return NSSize(width: lampSize + 2 * gap, height: 3 * lampSize + 4 * gap)
}

// Read every session's file and return the one state the light should show
func combinedState() -> String {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: sessionsFolder)) ?? []
    var states: [String] = []

    for name in names {
        let path = sessionsFolder + "/" + name
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
        guard let modified = attributes[.modificationDate] as? Date else { continue }

        let state = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutesOld = -modified.timeIntervalSinceNow / 60

        // "Working" with no news for 15 minutes: the reply was probably stopped halfway
        if state != "waiting" && minutesOld > 15 { continue }
        // Not heard from in 12 hours: the chat was probably closed
        if minutesOld > 12 * 60 { continue }

        states.append(state)
    }

    if states.contains("waiting") { return "waiting" }
    if states.contains("working") || states.contains("asking") { return "working" }
    return "idle"
}

class TrafficLightView: NSView {
    var state = "idle"
    var brightness: CGFloat = 1.0

    override func draw(_ dirtyRect: NSRect) {
        // Dark rounded box
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8 * scale, yRadius: 8 * scale)
        NSColor(white: 0.12, alpha: 0.92).setFill()
        box.fill()
        NSColor(white: 0.4, alpha: 1).setStroke()
        box.lineWidth = 1
        box.stroke()

        // Three lamps, top to bottom
        drawLamp(colour: .systemRed, row: 0, isOn: state == "waiting")
        drawLamp(colour: .systemYellow, row: 1, isOn: state == "working")
        drawLamp(colour: .systemGreen, row: 2, isOn: state == "idle")
    }

    func drawLamp(colour: NSColor, row: Int, isOn: Bool) {
        let lampSize = 18 * scale
        let gap = 5 * scale
        let x = (bounds.width - lampSize) / 2
        let y = bounds.height - gap - lampSize - CGFloat(row) * (lampSize + gap)  // y counts up from the bottom
        let lamp = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: lampSize, height: lampSize))
        let alpha = isOn ? brightness : 0.18
        colour.withAlphaComponent(alpha).setFill()
        lamp.fill()
    }

    // Right-click: a menu with the sizes and Quit
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for (index, size) in sizes.enumerated() {
            let item = NSMenuItem(title: size.name, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = size.scale == scale ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit light", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func pickSize(_ item: NSMenuItem) {
        scale = sizes[item.tag].scale
        UserDefaults.standard.set(Double(scale), forKey: "scale")
        resizeKeepingTopRight()
    }
}

// Change the window to the current scale without moving its top-right corner
func resizeKeepingTopRight() {
    let old = window.frame
    let size = lightSize()
    let newFrame = NSRect(x: old.maxX - size.width, y: old.maxY - size.height, width: size.width, height: size.height)
    window.setFrame(newFrame, display: true)
    light.needsDisplay = true
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon

// Start in the top-right corner, just under the menu bar
let startSize = lightSize()
let screen = NSScreen.main!.visibleFrame
let frame = NSRect(x: screen.maxX - startSize.width - 12, y: screen.maxY - startSize.height - 12,
                   width: startSize.width, height: startSize.height)

let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = true
window.level = .floating                                    // stays above other windows
window.collectionBehavior = [.canJoinAllSpaces, .stationary] // shows on every desktop
window.isMovableByWindowBackground = true

let light = TrafficLightView(frame: NSRect(origin: .zero, size: startSize))
light.autoresizingMask = [.width, .height]
window.contentView = light
window.setFrameAutosaveName("AgentLightTrafficLight")       // remembers where you dragged it
resizeKeepingTopRight()                                     // the saved spot may be from a different size
window.orderFrontRegardless()

var finishedAt: Date? = nil  // when everything last finished; nil once I've seen it

// 10 times a second: combine the sessions, set the flash or pulse, redraw only if something changed
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let newState = combinedState()
    let stateChanged = newState != light.state
    let justFinished = light.state == "working" && newState == "idle"
    light.state = newState
    let seconds = Date().timeIntervalSince1970

    if justFinished {
        finishedAt = Date()
    }
    if newState != "idle" {
        finishedAt = nil
    }

    // Stop the green flash once it has run 10 seconds and Claude is the app in front
    if let finished = finishedAt {
        let secondsSinceDone = -finished.timeIntervalSinceNow
        let claudeInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeAppID
        if secondsSinceDone > minimumFlashSeconds && claudeInFront {
            finishedAt = nil
            light.brightness = 1.0
            light.needsDisplay = true
        }
    }

    if light.state == "waiting" {
        light.brightness = 0.3 + 0.7 * CGFloat(abs(sin(seconds * 4)))   // fast flash
        light.needsDisplay = true
    } else if light.state == "working" {
        light.brightness = 0.55 + 0.45 * CGFloat(abs(sin(seconds * 2)))  // slow pulse
        light.needsDisplay = true
    } else if finishedAt != nil {
        light.brightness = 0.3 + 0.7 * CGFloat(abs(sin(seconds * 4)))   // done: fast flash until I look
        light.needsDisplay = true
    } else {
        light.brightness = 1.0
        if stateChanged {
            light.needsDisplay = true
        }
    }
}

app.run()
