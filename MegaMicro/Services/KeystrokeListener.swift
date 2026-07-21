import AppKit
import CoreGraphics

extension Modifiers {
    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.fn) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    /// Extract just the four standard modifiers from raw event flags —
    /// hardware events carry extra bits (fn on F-keys, non-coalesced, …)
    /// that must not break matching.
    init(cgFlags: CGEventFlags) {
        var mods: Modifiers = []
        if cgFlags.contains(.maskCommand) { mods.insert(.command) }
        if cgFlags.contains(.maskAlternate) { mods.insert(.option) }
        if cgFlags.contains(.maskControl) { mods.insert(.control) }
        if cgFlags.contains(.maskShift) { mods.insert(.shift) }
        self = mods
    }
}

/// System-wide keyboard listener. Primary path is a CGEventTap that can
/// CONSUME matched chords so the macro pad's F-key signals never leak into
/// the focused app.
///
/// CRITICAL: the tap runs on its own dedicated thread. An active event tap
/// routes session input through this process synchronously — hosting it on
/// the main run loop starves the app's own event delivery (window renders,
/// nothing is clickable). The callback therefore makes its consume decision
/// from a lock-protected trigger set and hops to the main thread only to
/// fire the action.
final class KeystrokeListener {
    enum Mode: String {
        case tap = "event tap (active)"
        case off = "off — grant Accessibility, then Retry"
    }

    /// Called on the MAIN thread for every matched (and consumed) trigger,
    /// with the press phase (down on keyDown, up on keyUp) so hold-style
    /// actions can mirror the physical key exactly.
    var onTrigger: ((Trigger, PressPhase) -> Void)?

    private(set) var mode: Mode = .off

    private let lock = NSLock()
    private var matchTriggers: Set<Trigger> = []

    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var tap: CFMachPort?

    /// Thread-safe update of the chord set the tap consumes.
    func updateTriggers(_ triggers: Set<Trigger>) {
        lock.lock()
        matchTriggers = triggers
        lock.unlock()
    }

    /// Tap or nothing. There is deliberately NO NSEvent global-monitor
    /// fallback: installing one without Input Monitoring permission wedges
    /// event delivery to this app (window renders, all input dead) — the bug
    /// behind every "app is frozen" report during development.
    func start() -> Mode {
        stop()
        mode = startTapThread() ? .tap : .off
        return mode
    }

    func stop() {
        if let tapRunLoop {
            CFRunLoopStop(tapRunLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        tapRunLoop = nil
        tapThread = nil
        mode = .off
    }

    // MARK: Tap (dedicated thread)

    private func startTapThread() -> Bool {
        let readySemaphore = DispatchSemaphore(value: 0)
        var created = false

        let thread = Thread { [weak self] in
            guard let self else {
                readySemaphore.signal()
                return
            }
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
            let callback: CGEventTapCallBack = { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<KeystrokeListener>.fromOpaque(refcon).takeUnretainedValue()
                return listener.handle(type: type, event: event)
            }
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
            else {
                readySemaphore.signal()
                return
            }
            self.tap = tap
            self.tapRunLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CGEvent.tapEnable(tap: tap, enable: true)
            created = true
            readySemaphore.signal()
            CFRunLoopRun()   // parked here until stop()
        }
        thread.name = "megamicro.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread

        _ = readySemaphore.wait(timeout: .now() + 2)
        return created
    }

    /// Runs on the tap thread — must stay fast and never touch app state.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

        let trigger = Trigger(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: Modifiers(cgFlags: event.flags))

        lock.lock()
        let matched = matchTriggers.contains(trigger)
        lock.unlock()

        guard matched else { return Unmanaged.passUnretained(event) }
        let phase: PressPhase = (type == .keyDown) ? .down : .up
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(trigger, phase)
        }
        return nil   // consume both phases so nothing leaks into apps
    }

}
