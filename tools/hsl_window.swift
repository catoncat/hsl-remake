import CoreGraphics
import Foundation

// Locate the original HSL Wine window. Selection is deliberately strict:
// when more than one plausible Wine game window exists, callers must pass an
// explicit window id instead of guessing and risking invalid evidence.

struct WindowInfo {
    let windowID: Int
    let pid: Int
    let owner: String
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var jsonObject: [String: Any] {
        [
            "window_id": windowID,
            "pid": pid,
            "owner": owner,
            "title": title,
            "x": x,
            "y": y,
            "width": width,
            "height": height,
        ]
    }
}

func printUsage() {
    print("usage: hsl_window [--wait SECONDS] [--window-id ID] [--list]")
    print("  --wait N       poll every 0.5s for up to N seconds")
    print("  --window-id N  select one exact CGWindow id")
    print("  --list         print all plausible Wine game-window candidates")
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

        // Wine's 640x480 client need not occupy 640x480 macOS points. A live
        // Wine 11 window measured 577x462 including chrome. Accept downscaling
        // to half size; retain owner/layer/aspect checks and fail on ambiguity.
        guard width >= 320, height >= 240 else { continue }
        let expectedClientHeight = width * 0.75
        let chromeHeight = height - expectedClientHeight
        guard chromeHeight >= -4, chromeHeight <= 120 else { continue }

        candidates.append(
            WindowInfo(
                windowID: id,
                pid: pid,
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

func printJSON(_ object: Any) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        fputs("error: failed to encode window information\n", stderr)
        exit(1)
    }
    print(string)
}

let rawArgs = Array(CommandLine.arguments.dropFirst())
if rawArgs.contains("help") || rawArgs.contains("--help") || rawArgs.contains("-h") {
    printUsage()
    exit(0)
}

var waitSeconds: Double = 0
var requestedWindowID: Int? = nil
var listOnly = false
var index = 0
while index < rawArgs.count {
    switch rawArgs[index] {
    case "--wait":
        guard index + 1 < rawArgs.count,
              let value = Double(rawArgs[index + 1]), value >= 0 else {
            printUsage()
            exit(2)
        }
        waitSeconds = value
        index += 2
    case "--window-id":
        guard index + 1 < rawArgs.count,
              let value = Int(rawArgs[index + 1]), value > 0 else {
            printUsage()
            exit(2)
        }
        requestedWindowID = value
        index += 2
    case "--list":
        listOnly = true
        index += 1
    default:
        fputs("error: unknown argument: \(rawArgs[index])\n", stderr)
        printUsage()
        exit(2)
    }
}

if requestedWindowID == nil,
   let environmentValue = ProcessInfo.processInfo.environment["HSL_WINDOW_ID"],
   let parsed = Int(environmentValue), parsed > 0 {
    requestedWindowID = parsed
}

let deadline = Date().addingTimeInterval(waitSeconds)
var candidates: [WindowInfo] = []
repeat {
    candidates = plausibleHSLWindows()
    if listOnly || requestedWindowID != nil || candidates.count == 1 { break }
    if Date() >= deadline { break }
    Thread.sleep(forTimeInterval: 0.5)
} while true

if listOnly {
    printJSON(candidates.map(\.jsonObject))
    exit(0)
}

if let requestedWindowID {
    guard let selected = candidates.first(where: { $0.windowID == requestedWindowID }) else {
        fputs("error: requested HSL window id \(requestedWindowID) was not found\n", stderr)
        printJSON(candidates.map(\.jsonObject))
        exit(1)
    }
    printJSON(selected.jsonObject)
    exit(0)
}

if candidates.count == 1 {
    printJSON(candidates[0].jsonObject)
    exit(0)
}

if candidates.isEmpty {
    fputs("error: HSL window not found\n", stderr)
} else {
    fputs("error: multiple plausible Wine game windows found; pass --window-id or HSL_WINDOW_ID\n", stderr)
    printJSON(candidates.map(\.jsonObject))
}
exit(1)
