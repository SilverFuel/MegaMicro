import SwiftUI

/// One physical control on the on-screen board: keycap, dial, joystick, or
/// touch strip, with its live LED glow and click/gesture affordances.
/// Visual language (soft neumorphic caps, halo glow) adapted from the
/// MIT-licensed microbridge UI, rebuilt natively.
struct ControlCapView: View {
    // The dashboard model drives all rendering on every platform; the macOS
    // app additionally injects AppState for physical-key interactions (presses,
    // shortcut mapping, glyph editing) that don't exist on iOS/watchOS.
    @Environment(DashboardModel.self) private var dashboard
    #if os(macOS)
    @Environment(AppState.self) private var appState
    #endif
    @Environment(\.agentBoardMode) private var agentBoardMode
    @Environment(\.colorScheme) private var colorScheme
    let spec: ControlSpec

    private var keySlot: Int? {
        guard spec.id.rawValue.hasPrefix("key.") else { return nil }
        return Int(spec.id.rawValue.dropFirst("key.".count))
    }

    private var ledColor: HSV? {
        guard let index = spec.ledIndex,
              index < dashboard.currentFrame.perLED.count else { return nil }
        return dashboard.currentFrame.perLED[index]
    }

    /// Route a physical-control interaction (macOS only; no-op elsewhere).
    private func activate(_ gesture: ControlGesture, phase: PressPhase = .down) {
        #if os(macOS)
        appState.controlActivated(spec.id, gesture: gesture, phase: phase)
        #endif
    }

    /// This control's custom legend, if any (from the synced layout settings).
    private var keyLegend: String? { dashboard.keyLegends[spec.id] }

    var body: some View {
        switch spec.kind {
        case .key: keyCap
        case .dial: dial
        case .joystick: joystick
        case .touchStrip: touchStrip
        case .touchButton: touchButton
        }
    }

    // MARK: Touch button (round black profile-switch button)

    private var touchButton: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.05)],
                                 center: .topLeading, startRadius: 1, endRadius: 26))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
            .frame(maxWidth: 34, maxHeight: 34)
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        activate(.press, phase: .down)
                    }
                    .onEnded { _ in
                        pressed = false
                        activate(.press, phase: .up)
                    })
            .platformHelp(helpText(for: .press))
    }

    // MARK: Cap styling
    // The physical device is white — it stays white in dark mode too, where
    // it pops against the dark window (like the real thing on a dark desk).

    private var capBase: Color { Color(white: 0.99) }
    private var capBaseBottom: Color { Color(white: 0.93) }
    /// Legend ink pinned dark: caps are always white, so `.primary` (white
    /// in dark mode) would vanish.
    private var legendInk: Color { Color.black.opacity(0.68) }

    /// LED halo color at full value; intensity 0–1 from the rendered value.
    private var glow: (color: Color, intensity: Double)? {
        guard let led = ledColor, led.v > 0 else { return nil }
        return (Color(hsv: HSV(h: led.h, s: led.s, v: 255)), Double(led.v) / 255.0)
    }

    private func capShape(cornerRadius: CGFloat = 10) -> some View {
        let glowColor: Color = glow?.color ?? .clear
        let glowIntensity: Double = glow?.intensity ?? 0
        let fillGradient = LinearGradient(
            colors: [capBase, capBaseBottom], startPoint: .top, endPoint: .bottom)
        let borderShape = RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        // LED tint bleeding through the translucent cap.
        let tintShape = RoundedRectangle(cornerRadius: cornerRadius)
            .fill(glowColor.opacity(glowIntensity * 0.28))
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fillGradient)
            .overlay(borderShape)
            .overlay(tintShape)
            // Depth: soft drop shadow…
            .shadow(color: Color.black.opacity(0.16), radius: 2, y: 1.5)
            // …plus the state-colored halo around the cap.
            .shadow(color: glowColor.opacity(glowIntensity * 0.9),
                    radius: 9 * glowIntensity)
    }

    // MARK: Key

    @State private var pressed = false
    @State private var dropTargeted = false
    @State private var hovering = false
    @State private var tooltipVisible = false

    @ViewBuilder
    private var keyCap: some View {
        let base = ZStack {
            capShape()
            keyContent
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 3 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(pressed ? 0.94 : (dropTargeted ? 1.06 : 1))
        .animation(.easeOut(duration: 0.08), value: pressed)
        .animation(.easeOut(duration: 0.12), value: dropTargeted)
        // Publish this cap as the hovered control after a short delay; the
        // board draws the styled floating card. Replaces the plain `.help`.
        .platformHover { inside in
            hovering = inside
            if inside {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(380))
                    if hovering { tooltipVisible = true }
                }
            } else {
                tooltipVisible = false
            }
        }
        .preference(key: HoveredControlKey.self, value: tooltipVisible ? spec.id : nil)

        if agentBoardMode {
            let occupant = keySlot.flatMap { dashboard.occupantLabel(forSlot: $0) }
            let canMove = keySlot != nil && occupant != nil && spec.ledIndex != nil
            base
                .onTapGesture {
                    if let slot = keySlot { _ = dashboard.focus(onSlot: slot) }
                }
                .platformKeyDrop(onDrop: { dashboard.handleDrop($0, onto: spec.id) },
                                 isTargeted: { dropTargeted = $0 })
                .modifier(GlyphEditMenu(controlID: spec.id))
                .platformDraggable("move:\(keySlot ?? 0)", enabled: canMove)
        } else {
            base
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !pressed else { return }
                            pressed = true
                            activate(.press, phase: .down)
                        }
                        .onEnded { _ in
                            pressed = false
                            activate(.press, phase: .up)
                        })
                .platformKeyDrop(onDrop: { dashboard.handleDrop($0, onto: spec.id) },
                                 isTargeted: { dropTargeted = $0 })
        }
    }

    @ViewBuilder
    private var keyContent: some View {
        if agentBoardMode {
            switch keySlot.flatMap({ dashboard.occupantGlyph(forSlot: $0) }) {
            case .brand(let asset):
                BrandIcon(asset: asset, size: 22, tint: legendInk)
            case .brandPair(let primary, let secondary):
                #if os(watchOS)
                // The watch face is tiny — show only the tool (agent) mark,
                // larger, so it reads clearly without the environment overlap.
                BrandIcon(asset: secondary, size: 20, tint: legendInk)
                #else
                // Environment + tool on one key (e.g. Conductor · Codex,
                // Ghostty · Claude).
                HStack(spacing: 4) {
                    BrandIcon(asset: primary, size: 18, tint: legendInk)
                    BrandIcon(asset: secondary, size: 18, tint: legendInk)
                }
                #endif
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 12))
                    .foregroundStyle(legendInk.opacity(0.8))
            case nil:
                // Empty agent-hosting keys stay visually blank. Printed
                // landmarks remain only on dedicated non-agent controls.
                if !spec.hostsAgents,
                   let legend = keyLegend ?? spec.legend,
                   !legend.isEmpty {
                    legendView(legend).opacity(0.28)
                }
            }
        } else if let custom = keyLegend, !custom.isEmpty {
            legendView(custom)
        } else if let printed = spec.legend, !printed.isEmpty {
            // The layout's printed-cap glyph (matches the physical keycaps).
            legendView(printed)
        } else {
            Text(actionHint)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(legendInk.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 3)
        }
    }

    /// Legend strings support "sf:<symbol>" (SF Symbol) and "brand:<asset>"
    /// (bundled brand SVG) in addition to plain text.
    @ViewBuilder
    private func legendView(_ legend: String) -> some View {
        if legend.hasPrefix("sf:") {
            Image(systemName: String(legend.dropFirst(3)))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(legendInk)
        } else if legend.hasPrefix("brand:") {
            BrandIcon(asset: String(legend.dropFirst(6)), size: 15, tint: legendInk)
        } else {
            Text(legend)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(legendInk)
        }
    }

    private var actionHint: String {
        #if os(macOS)
        let action = appState.action(for: spec.id, gesture: .press)
        if case .none = action { return "" }
        return action.summary
        #else
        return ""
        #endif
    }

    // MARK: Dial

    private var dial: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [capBase, capBaseBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.2), radius: 2.5, y: 2)
                Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                // Knob indicator line, like the real dial's notch.
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 2.5, height: 11)
                    .offset(y: -9)
                    .rotationEffect(.degrees(35))
            }
            .contentShape(Circle())
            .onTapGesture { activate(.press) }
            .platformHelp(helpText(for: .press))
            HStack(spacing: 4) {
                gestureButton("arrow.counterclockwise", .counterclockwise)
                gestureButton("arrow.clockwise", .clockwise)
            }
        }
    }

    // MARK: Joystick

    private var joystick: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.25), Color(white: 0.08)],
                                     center: .topLeading, startRadius: 2, endRadius: 46))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                .padding(5)
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(spacing: 0) {
                gestureButton("chevron.up", .up, light: true)
                HStack(spacing: 14) {
                    gestureButton("chevron.left", .left, light: true)
                    gestureButton("chevron.right", .right, light: true)
                }
                gestureButton("chevron.down", .down, light: true)
            }
        }
    }

    // MARK: Touch strip

    private var touchStrip: some View {
        ZStack {
            Capsule()
                .fill(Color.controlSurface)
                .overlay(Capsule().strokeBorder(.quaternary))
            HStack {
                gestureButton("chevron.backward.2", .swipeLeft)
                Spacer()
                Text("touch strip").font(.caption2).foregroundStyle(Color.black.opacity(0.35))
                Spacer()
                gestureButton("chevron.forward.2", .swipeRight)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: Helpers

    private func gestureButton(_ symbol: String, _ gesture: ControlGesture, light: Bool = false) -> some View {
        Button {
            activate(gesture)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(light ? Color.white.opacity(0.75) : Color.black.opacity(0.45))
                .frame(width: 16, height: 14)
        }
        .buttonStyle(.plain)
        .platformHelp(helpText(for: gesture))
    }

    private func helpText(for gesture: ControlGesture) -> String {
        #if os(macOS)
        let action = appState.action(for: spec.id, gesture: gesture)
        return "\(spec.id.rawValue) \(gesture.rawValue): \(action.summary)"
        #else
        return ""
        #endif
    }
}

/// The "Change Key Glyph…" context menu — macOS only (glyph editing lives in
/// the desktop app). A no-op passthrough elsewhere so the shared cap compiles.
private struct GlyphEditMenu: ViewModifier {
    let controlID: ControlID
    #if os(macOS)
    @Environment(AppState.self) private var appState
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content.contextMenu {
            Button("Change Key Glyph…") { appState.glyphTarget = controlID }
        }
        #else
        content
        #endif
    }
}
