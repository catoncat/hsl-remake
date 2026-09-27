import Foundation
import ScreenCaptureKit
import CoreGraphics
import AVFoundation

// Bounded, explicit-window reference recording. Never captures a display or microphone.
// Build: swiftc -parse-as-library tools/hsl_record_window.swift -o ignored/bin/hsl_record_window
@available(macOS 15.0, *)
final class RecordingDelegate: NSObject, SCRecordingOutputDelegate {
    var finished = false
    var failure: Error?
    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        print("RECORDING_STARTED")
        fflush(stdout)
    }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) { finished = true }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        failure = error
        finished = true
    }
}

@main
struct WindowRecorder {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["--list"] {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let windows: [[String: Any]] = content.windows.compactMap { window in
                    guard let owner = window.owningApplication,
                          owner.applicationName.lowercased().contains("wine") || owner.applicationName.lowercased().contains("godot") else { return nil }
                    return ["window": window.windowID, "title": window.title ?? "", "owner": owner.applicationName,
                            "builtin": content.displays.contains(where: { CGDisplayIsBuiltin($0.displayID) != 0 && $0.frame.contains(window.frame) })]
                }
                print(String(data: try JSONSerialization.data(withJSONObject: windows, options: [.sortedKeys]), encoding: .utf8)!)
                return
            }
            if args == ["--help"] {
                print("hsl_record_window --list | WINDOW_ID SECONDS OUTPUT.mp4 [--no-audio]\nExplicit game window on built-in display only; 1..60 seconds; no overwrite; app audio, no microphone. --no-audio records video only (needed for silent Wine windows: with audio enabled the recording output stalls after ~1 s of frames).")
                return
            }
            let noAudio = args.count == 4 && args[3] == "--no-audio"
            guard args.count == 3 || noAudio, let id = UInt32(args[0]), let seconds = Double(args[1]),
                  seconds.isFinite, (1...60).contains(seconds), args[2].hasSuffix(".mp4") else {
                throw NSError(domain: "Recorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Use --help for arguments"])
            }
            let url = URL(fileURLWithPath: args[2]).standardizedFileURL
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "Recorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Output already exists"])
            }
            guard #available(macOS 15.0, *) else {
                throw NSError(domain: "Recorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "macOS 15 or newer required"])
            }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }),
                  let owner = window.owningApplication,
                  owner.applicationName.lowercased().contains("wine") || owner.applicationName.lowercased().contains("godot") else {
                throw NSError(domain: "Recorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Explicit Wine/Godot window not found"])
            }
            guard content.displays.contains(where: { CGDisplayIsBuiltin($0.displayID) != 0 && $0.frame.contains(window.frame) }) else {
                throw NSError(domain: "Recorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Move game window wholly onto built-in display first"])
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            config.capturesAudio = !noAudio
            config.captureMicrophone = false
            if !noAudio {
                config.sampleRate = 48000
                config.channelCount = 2
            }
            let delegate = RecordingDelegate()
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = url
            let recording = SCRecordingOutput(configuration: recordingConfig, delegate: delegate)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addRecordingOutput(recording)
            try await stream.startCapture()
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            try await stream.stopCapture()
            let deadline = Date().addingTimeInterval(10)
            while !delegate.finished && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            if let failure = delegate.failure { throw failure }
            guard delegate.finished else { throw NSError(domain: "Recorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recording did not finalize"] ) }
            print("RECORDING_SAVED \(url.path)")
        } catch {
            fputs("RECORDING_ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
