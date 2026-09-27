import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// macOS CGEvent input probe for the Wine HSL game window.
//
// The original game polls hardware-style input, so all supported commands use
// the .cghidEventTap stream. Click commands may temporarily move the real
// cursor; restored variants return it to the saved position afterwards.
//
// Usage:
//   hsl_input click X Y     - left click at client coords (game viewport)
//   hsl_input menuclick X Y - battle-menu left click (same path as click)
//   hsl_input menurclick X Y - battle-menu right click (same path as rclick)
//   hsl_input move X Y      - HID mouse move to client coords, no click
//   hsl_input rawclick X Y  - HID left click at client coords, no focus restore
//   hsl_input rawholdclick X Y MS - HID left click with explicit hold duration
//   hsl_input rawrclick X Y - HID right click at client coords, no focus restore
//   hsl_input rclick X Y    - right click at client coords
//   hsl_input key space      - press a key (space/return/escape/up/down/left/right)
//   hsl_input keyhid space   - press a HID key via .cghidEventTap
//   hsl_input confirm        - focus game with a center click, then HID Space
//   hsl_input find           - print window info
//
// Compile:
//   swiftc -O -o tools/hsl_input tools/hsl_input.swift -framework AppKit

struct WindowInfo {
    let windowID: Int
    let pid: pid_t
    let owner: String
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

func plausibleHSLWindows() -> [WindowInfo] {
    guard let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var candidates: [WindowInfo] = []
    for window in windowList {
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        let normalizedOwner = owner.lowercased()
        let layer = window[kCGWindowLayer as String] as? Int ?? -1
        guard layer == 0 else { continue }
        guard normalizedOwner == "wine" || normalizedOwner == "wine64" else { continue }
        guard let id = window[kCGWindowNumber as String] as? Int,
              let pid = window[kCGWindowOwnerPID as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double,
              let y = bounds["Y"] as? Double,
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else { continue }

        // Keep in sync with hsl_window.swift: Wine client pixels and macOS
        // window points may differ (observed 640x480 client, 577x462 window).
        guard width >= 320, height >= 240 else { continue }
        let expectedClientHeight = width * 0.75
        let chromeHeight = height - expectedClientHeight
        guard chromeHeight >= -4, chromeHeight <= 120 else { continue }

        candidates.append(
            WindowInfo(
                windowID: id,
                pid: pid_t(pid),
                owner: owner,
                title: window[kCGWindowName as String] as? String ?? "",
                x: Int(x.rounded()),
                y: Int(y.rounded()),
                width: Int(width.rounded()),
                height: Int(height.rounded())
            )
        )
    }
    return candidates.sorted { lhs, rhs in
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.windowID < rhs.windowID
    }
}

func selectHSLWindow(requestedWindowID: Int?) -> WindowInfo? {
    let candidates = plausibleHSLWindows()
    if let requestedWindowID {
        if let selected = candidates.first(where: { $0.windowID == requestedWindowID }) {
            return selected
        }
        fputs("error: requested HSL window id \(requestedWindowID) was not found\n", stderr)
        return nil
    }
    if candidates.count == 1 {
        return candidates[0]
    }
    if candidates.isEmpty {
        fputs("error: HSL window not found\n", stderr)
    } else {
        fputs("error: multiple plausible Wine game windows found; pass --window-id or HSL_WINDOW_ID\n", stderr)
        for candidate in candidates {
            fputs(
                "  window_id=\(candidate.windowID) pid=\(candidate.pid) title=\(candidate.title) " +
                "pos=(\(candidate.x),\(candidate.y)) size=\(candidate.width)x\(candidate.height)\n",
                stderr
            )
        }
    }
    return nil
}

func clientToScreen(_ win: WindowInfo, cx: Int, cy: Int) -> CGPoint {
    let logicalWidth = 640.0
    let logicalHeight = 480.0
    let scale = Double(win.width) / logicalWidth
    let clientHeight = logicalHeight * scale
    let chromeHeight = max(0.0, Double(win.height) - clientHeight)
    return CGPoint(
        x: Double(win.x) + Double(cx) * scale,
        y: Double(win.y) + chromeHeight + Double(cy) * scale
    )
}

@discardableResult
func sendClick(_ win: WindowInfo, cx: Int, cy: Int, right: Bool = false) -> Bool {
    let pt = clientToScreen(win, cx: cx, cy: cy)

    let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
    let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
    let button: CGMouseButton = right ? .right : .left

    // Save current cursor position
    let saved = CGEvent(source: nil)!.location

    // Save frontmost app
    let workspace = NSWorkspace.shared
    let frontApp = workspace.frontmostApplication

    guard let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                             mouseCursorPosition: pt, mouseButton: button),
          let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                           mouseCursorPosition: pt, mouseButton: button),
          let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                mouseCursorPosition: saved, mouseButton: .left) else {
        fputs("error: failed to create click events\n", stderr)
        return false
    }

    // Post to HID tap (game only reads from here)
    down.post(tap: .cghidEventTap)
    usleep(100_000)  // 100ms hold for game to poll
    up.post(tap: .cghidEventTap)

    // Immediately restore cursor position
    usleep(10_000)
    restore.post(tap: .cghidEventTap)

    // Restore frontmost app
    usleep(50_000)
    frontApp?.activate()
    return true
}

@discardableResult
func sendRawClick(_ win: WindowInfo, cx: Int, cy: Int, right: Bool = false, holdMicros: useconds_t = 180_000) -> Bool {
    let pt = clientToScreen(win, cx: cx, cy: cy)
    let moveType: CGEventType = .mouseMoved
    let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
    let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
    let button: CGMouseButton = right ? .right : .left

    guard let move = CGEvent(mouseEventSource: nil, mouseType: moveType,
                             mouseCursorPosition: pt, mouseButton: button),
          let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                             mouseCursorPosition: pt, mouseButton: button),
          let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                           mouseCursorPosition: pt, mouseButton: button) else {
        fputs("error: failed to create raw click events\n", stderr)
        return false
    }

    down.setIntegerValueField(.mouseEventClickState, value: 1)
    up.setIntegerValueField(.mouseEventClickState, value: 1)

    move.post(tap: .cghidEventTap)
    usleep(100_000)
    down.post(tap: .cghidEventTap)
    usleep(holdMicros)
    up.post(tap: .cghidEventTap)
    return true
}

@discardableResult
func sendMouseMove(_ win: WindowInfo, cx: Int, cy: Int) -> Bool {
    let pt = clientToScreen(win, cx: cx, cy: cy)
    guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                             mouseCursorPosition: pt, mouseButton: .left) else {
        fputs("error: failed to create mouse move event\n", stderr)
        return false
    }
    move.post(tap: .cghidEventTap)
    return true
}

func keyCodeFor(_ name: String) -> (CGKeyCode, Bool)? {
    switch name.lowercased() {
    case "space":      return (49, true)
    case "return", "enter": return (36, true)
    case "escape", "esc":   return (53, true)
    case "up":         return (126, true)
    case "down":       return (125, true)
    case "left":       return (123, true)
    case "right":      return (124, true)
    case "tab":        return (48, true)
    default:
        if name.count == 1, let ch = name.first, ch.isASCII {
            let code: CGKeyCode
            switch ch {
            case "a": code = 0;  case "b": code = 11; case "c": code = 8
            case "d": code = 2;  case "e": code = 14; case "f": code = 3
            case "g": code = 5;  case "h": code = 4;  case "i": code = 34
            case "j": code = 38; case "k": code = 40; case "l": code = 37
            case "m": code = 46; case "n": code = 45; case "o": code = 31
            case "p": code = 35; case "q": code = 12; case "r": code = 15
            case "s": code = 1;  case "t": code = 17; case "u": code = 32
            case "v": code = 9;  case "w": code = 13; case "x": code = 7
            case "y": code = 16; case "z": code = 6
            default: return nil
            }
            return (code, true)
        }
        return nil
    }
}

@discardableResult
func sendHIDKey(_ name: String) -> Bool {
    guard let (keyCode, _) = keyCodeFor(name) else {
        fputs("error: unknown key '\(name)'\n", stderr)
        return false
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
        fputs("error: failed to create HID keyboard event\n", stderr)
        return false
    }
    down.post(tap: .cghidEventTap)
    usleep(160_000)
    up.post(tap: .cghidEventTap)
    return true
}

// --- Main ---

func printUsage() {
    fputs("usage: hsl_input [--window-id ID] <command> [args...]\n", stderr)
    fputs("  find            - print selected window info\n", stderr)
    fputs("  click X Y       - left click at 640x480 logical client coords\n", stderr)
    fputs("  menuclick X Y   - battle-menu left click (same path as click)\n", stderr)
    fputs("  menurclick X Y  - battle-menu right click (same path as rclick)\n", stderr)
    fputs("  move X Y        - HID mouse move to client coords, no click\n", stderr)
    fputs("  rawclick X Y    - HID left click at client coords, no focus restore\n", stderr)
    fputs("  rawholdclick X Y MS - HID left click with explicit hold duration\n", stderr)
    fputs("  rawrclick X Y   - HID right click at client coords, no focus restore\n", stderr)
    fputs("  rclick X Y      - right click at client coords\n", stderr)
    fputs("  keyhid <name>   - press HID key through cghidEventTap\n", stderr)
    fputs("\n", stderr)
    fputs("When several Wine windows exist, --window-id is required.\n", stderr)
}

var commandArgs = Array(CommandLine.arguments.dropFirst())
if commandArgs.contains("help") || commandArgs.contains("--help") || commandArgs.contains("-h") {
    printUsage()
    exit(0)
}

var requestedWindowID: Int? = nil
if commandArgs.count >= 2, commandArgs[0] == "--window-id" {
    guard let value = Int(commandArgs[1]), value > 0 else {
        printUsage()
        exit(2)
    }
    requestedWindowID = value
    commandArgs.removeFirst(2)
} else if let environmentValue = ProcessInfo.processInfo.environment["HSL_WINDOW_ID"],
          let value = Int(environmentValue), value > 0 {
    requestedWindowID = value
}

guard let command = commandArgs.first else {
    printUsage()
    exit(2)
}
let operands = Array(commandArgs.dropFirst())

guard let win = selectHSLWindow(requestedWindowID: requestedWindowID) else {
    exit(1)
}

if command != "find" && !AXIsProcessTrusted() {
    fputs(
        "error: Accessibility permission is required for tools/hsl_input; " +
        "grant it in System Settings > Privacy & Security > Accessibility\n",
        stderr
    )
    exit(3)
}

func coordinates(_ values: [String], usage: String) -> (Int, Int) {
    guard values.count == 2, let x = Int(values[0]), let y = Int(values[1]),
          (0..<640).contains(x), (0..<480).contains(y) else {
        fputs("usage: \(usage) (X=0..639, Y=0..479)\n", stderr)
        exit(2)
    }
    return (x, y)
}

switch command {
case "find":
    guard operands.isEmpty else { printUsage(); exit(2) }
    print(
        "window_id=\(win.windowID) pid=\(win.pid) owner=\(win.owner) title=\(win.title) " +
        "pos=(\(win.x),\(win.y)) size=\(win.width)x\(win.height)"
    )

case "click":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] click X Y")
    guard sendClick(win, cx: x, cy: y) else { exit(1) }
    print("click \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "menuclick":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] menuclick X Y")
    guard sendClick(win, cx: x, cy: y) else { exit(1) }
    print("menuclick \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "menurclick":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] menurclick X Y")
    guard sendClick(win, cx: x, cy: y, right: true) else { exit(1) }
    print("menurclick \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "move":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] move X Y")
    guard sendMouseMove(win, cx: x, cy: y) else { exit(1) }
    print("move \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "rawclick":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] rawclick X Y")
    guard sendRawClick(win, cx: x, cy: y) else { exit(1) }
    print("rawclick \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "rawholdclick":
    guard operands.count == 3,
          let x = Int(operands[0]), let y = Int(operands[1]),
          (0..<640).contains(x), (0..<480).contains(y),
          let milliseconds = Int(operands[2]), milliseconds >= 1 else {
        fputs("usage: hsl_input [--window-id ID] rawholdclick X Y MS\n", stderr)
        exit(2)
    }
    guard sendRawClick(win, cx: x, cy: y, holdMicros: useconds_t(milliseconds * 1000)) else { exit(1) }
    print("rawholdclick \(x),\(y),\(milliseconds)ms -> window \(win.windowID) pid \(win.pid)")

case "rawrclick":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] rawrclick X Y")
    guard sendRawClick(win, cx: x, cy: y, right: true) else { exit(1) }
    print("rawrclick \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "rclick":
    let (x, y) = coordinates(operands, usage: "hsl_input [--window-id ID] rclick X Y")
    guard sendClick(win, cx: x, cy: y, right: true) else { exit(1) }
    print("rclick \(x),\(y) -> window \(win.windowID) pid \(win.pid)")

case "keyhid":
    guard operands.count == 1 else {
        fputs("usage: hsl_input [--window-id ID] keyhid <name>\n", stderr)
        exit(2)
    }
    guard sendHIDKey(operands[0]) else { exit(1) }
    print("keyhid \(operands[0]) -> window \(win.windowID) pid \(win.pid)")

case "help", "--help", "-h":
    printUsage()

default:
    fputs("unknown command: \(command)\n", stderr)
    exit(2)
}
