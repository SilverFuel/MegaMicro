import AppKit
import CoreGraphics

/// Executes mapped actions: keystroke injection, URL opening (conductor://
/// deep links), shell commands, and literal text typing.
@MainActor
final class ExecutionEngine {
    var log: (String) -> Void = { _ in }

    /// `preferredBundleID` is the active profile's app: when a keystroke
    /// targets .frontmost but that app isn't frontmost (e.g. simulate-mode
    /// click, or pressing a Conductor key while in a browser), we activate it
    /// first so the shortcut lands where the user meant it to.
    /// `phase` matters only for .holdKeystroke; every other action fires on
    /// .down and ignores .up.
    func perform(_ action: Action, phase: PressPhase = .down, preferredBundleID: String? = nil) {
        if case .holdKeystroke(let chord, _) = action {
            switch phase {
            case .down: postPhase(chord, keyDown: true)
            case .up: postPhase(chord, keyDown: false)
            }
            return
        }
        guard phase == .down else { return }
        switch action {
        case .none, .holdKeystroke, .cycleProfile:
            break   // cycleProfile is handled by AppState before the engine
        case .keystroke(let chord, let target):
            sendChord(chord, target: target, preferredBundleID: preferredBundleID)
        case .openURL(let urlString):
            guard let url = URL(string: urlString) else {
                log("bad URL: \(urlString)")
                return
            }
            NSWorkspace.shared.open(url)
        case .shell(let command):
            runShell(command)
        case .typeText(let text):
            Task { await self.typeText(text) }
        case .switchProfile:
            break   // handled by AppState before reaching the engine
        }
    }

    // MARK: Keystrokes

    private func sendChord(_ chord: KeyChord, target: TargetApp, preferredBundleID: String?) {
        var bundleToActivate: String?
        switch target {
        case .bundleID(let id):
            bundleToActivate = id
        case .frontmost:
            if let preferred = preferredBundleID,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier != preferred {
                bundleToActivate = preferred
            }
        }

        Task {
            if let bundleID = bundleToActivate {
                await self.activate(bundleID: bundleID)
            }
            self.post(chord)
        }
    }

    private func activate(bundleID: String) async {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            log("app not found: \(bundleID)")
            return
        }
        // Give the app a beat to take key focus before the keystroke lands.
        try? await Task.sleep(for: .milliseconds(180))
    }

    /// One half of a held chord (push-to-talk down or up).
    private func postPhase(_ chord: KeyChord, keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: keyDown) else { return }
        event.flags = chord.modifiers.cgFlags
        event.post(tap: .cghidEventTap)
    }

    private func post(_ chord: KeyChord) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: false)
        else { return }
        down.flags = chord.modifiers.cgFlags
        up.flags = chord.modifiers.cgFlags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: Text

    private func typeText(_ text: String) async {
        let source = CGEventSource(stateID: .hidSystemState)
        for chunk in text.utf16.chunked(into: 20) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            var units = chunk
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    // MARK: Shell

    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let logger = log
        process.terminationHandler = { proc in
            let status = proc.terminationStatus
            Task { @MainActor in
                logger("$ \(command) → exit \(status)")
            }
        }
        do {
            try process.run()
        } catch {
            log("shell failed: \(error.localizedDescription)")
        }
    }
}

private extension Collection where Element == UInt16 {
    func chunked(into size: Int) -> [[UInt16]] {
        var result: [[UInt16]] = []
        var chunk: [UInt16] = []
        for unit in self {
            chunk.append(unit)
            if chunk.count == size {
                result.append(chunk)
                chunk = []
            }
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
}
