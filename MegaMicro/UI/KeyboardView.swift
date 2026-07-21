import SwiftUI

extension Color {
    init(hsv: HSV) {
        let rgb = hsv.rgb
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// When true (Agents pane), keys act as agent tiles: they show their
/// occupant, drag to move agents between keys, and don't fire actions.
private struct AgentBoardModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var agentBoardMode: Bool {
        get { self[AgentBoardModeKey.self] }
        set { self[AgentBoardModeKey.self] = newValue }
    }
}

/// Graphical representation of the connected keyboard. Renders any
/// KeyboardLayout; LED colors come live from AppState.currentFrame, so this
/// doubles as the hardware simulator until the real device arrives.
struct KeyboardView: View {
    @Environment(DashboardModel.self) private var dashboard
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.agentBoardMode) private var agentBoardMode

    @State private var hoveredControl: ControlID?
    @State private var tooltipSize: CGSize = .zero

    private let gap: CGFloat = 8

    // The device stays white in dark mode, like the physical hardware.
    private var chassisColor: Color { Color(white: 0.945) }

    /// Vertical text hugging the device's inner edge, like the silkscreen on
    /// the real board. The 8pt-wide frame keeps the rotated text's layout box
    /// pinned to the edge instead of spanning the row.
    private func sideEngraving(_ text: String, degrees: Double) -> some View {
        Text(text)
            .font(.system(size: 5.5, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.4))
            .fixedSize()
            .rotationEffect(.degrees(degrees))
            .frame(width: 8)
    }

    /// The physical details that make it read as the real device: corner
    /// screws, side engravings, status LEDs, the top arrow.
    @ViewBuilder
    private func chassisDecor(boardW: CGFloat, boardH: CGFloat, isCodex: Bool) -> some View {
        let screw = Circle()
            .fill(Color.black.opacity(0.55))
            .frame(width: 5, height: 5)
        ZStack {
            VStack {
                HStack { screw; Spacer(); screw }
                Spacer()
                HStack { screw; Spacer(); screw }
            }
            .padding(5)

            if isCodex {
                Image(systemName: "arrowtriangle.up")
                    .font(.system(size: 6))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)

                sideEngraving("Work Louder | OpenAI  2026", degrees: -90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 1.5)

                sideEngraving("You can just build things", degrees: 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 1.5)

                Text("Let’s build")
                    .font(.system(size: 5.5, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)

                // The three tiny status LEDs beside the mode key — lit count
                // shows which profile is active.
                let activeIndex = dashboard.activeProfileIndex
                VStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i <= min(activeIndex, 2) ? Color.green.opacity(0.85) : Color.black.opacity(0.2))
                            .frame(width: 2.8, height: 2.8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 3)
                .padding(.bottom, boardH * 0.18)
            }
        }
    }

    /// The floating tooltip card, placed above (or below, near the top row) the
    /// hovered control. Drawn last in the board ZStack so it floats over keys.
    @ViewBuilder
    private func tooltipOverlay(unit: CGFloat, boardW: CGFloat, boardH: CGFloat) -> some View {
        if let id = hoveredControl,
           let spec = dashboard.layout.controls.first(where: { $0.id == id }),
           let data = tooltipData(for: spec) {
            let x0 = spec.frame.x * unit + 3
            let y0 = spec.frame.y * unit + 3
            let w = spec.frame.w * unit - 6
            let h = spec.frame.h * unit - 6
            let centerX = min(max(x0 + w / 2, tooltipSize.width / 2), boardW - tooltipSize.width / 2)
            let fitsAbove = y0 - tooltipSize.height - 8 >= -12
            let centerY = fitsAbove
                ? y0 - 8 - tooltipSize.height / 2
                : y0 + h + 8 + tooltipSize.height / 2

            TooltipCard(data: data)
                .background(GeometryReader { g in
                    Color.clear.preference(key: TooltipSizeKey.self, value: g.size)
                })
                .onPreferenceChange(TooltipSizeKey.self) { tooltipSize = $0 }
                .position(x: centerX, y: centerY)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                .zIndex(100)
        }
    }

    /// Assemble structured tooltip content for a control: live agent detail on
    /// occupied agent keys, an assignment hint on bound-but-idle keys, or the
    /// mapped action in normal (non-agent-board) mode.
    private func tooltipData(for spec: ControlSpec) -> TooltipData? {
        let slot: Int? = spec.id.rawValue.hasPrefix("key.")
            ? Int(spec.id.rawValue.dropFirst("key.".count)) : nil

        if agentBoardMode, let slot {
            if let session = dashboard.assignedSession(forSlot: slot) {
                let color = dashboard.rgbRules.spec(for: session.state).color
                var rows: [TooltipData.Row] = []
                rows.append(.init(label: "Task", value: session.task ?? "Current agent session"))
                rows.append(.init(label: "Model", value: session.model ?? "Not reported"))
                rows.append(.init(label: "Project", value: dashboard.projectName(for: session) ?? "Unknown"))
                rows.append(.init(label: "Active", value: dashboard.elapsed(since: session.startedAt)))
                return TooltipData(
                    title: session.agent ?? session.source,
                    stateText: session.state.wireName,
                    accent: Color(hsv: HSV(h: color.h, s: color.s, v: 255)),
                    rows: rows,
                    footer: "Press to jump to agent")
            }
            if let occupant = dashboard.occupantLabel(forSlot: slot) {
                return TooltipData(
                    title: occupant, stateText: nil, accent: nil,
                    rows: [.init(label: "Key", value: "\(slot + 1)")],
                    footer: "Drag to another key to move")
            }
            return TooltipData(
                title: "Key \(slot + 1)", stateText: "free", accent: nil,
                rows: [], footer: "Auto pool — drag an agent here")
        }

        // Normal (non-agent) mode shows the mapped action — macOS only, since
        // key mapping lives in the desktop app.
        #if os(macOS)
        let title = dashboard.keyLegends[spec.id] ?? spec.legend ?? spec.id.rawValue
        return tooltipActionData(for: spec, title: title)
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private func tooltipActionData(for spec: ControlSpec, title: String) -> TooltipData? {
        let action = macAppState?.action(for: spec.id, gesture: .press) ?? .none
        if case .none = action { return nil }
        return TooltipData(title: title, stateText: nil, accent: nil,
                           rows: [.init(label: "Press", value: action.summary)], footer: nil)
    }
    @Environment(AppState.self) private var macAppState: AppState?
    #endif

    var body: some View {
        let layout = dashboard.layout
        GeometryReader { geo in
            let unit = min(geo.size.width / layout.columns, geo.size.height / layout.rows)
            let boardW = layout.columns * unit
            let boardH = layout.rows * unit
            let glow = dashboard.currentFrame.underglow
            let isCodex = layout.id == CodexMicroLayout.layout.id
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(chassisColor)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.08)))
                    .overlay(chassisDecor(boardW: boardW, boardH: boardH, isCodex: isCodex))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    // Perimeter underglow halo, mirroring the device's
                    // rgblight. Drawn as a background (never affects layout)
                    // and always present (opacity 0 when off) so the board
                    // never shifts when the glow turns on.
                    .background(
                        RoundedRectangle(cornerRadius: 26)
                            .fill(Color(hsv: HSV(h: glow.h, s: glow.s, v: 255)))
                            .padding(-gap * 1.6)
                            .blur(radius: 16)
                            .opacity(glow.v > 0 ? Double(glow.v) / 255.0 * 0.85 : 0))
                    .frame(width: boardW + gap * 2, height: boardH + gap * 2)
                    .offset(x: -gap, y: -gap)

                ForEach(layout.controls) { spec in
                    ControlCapView(spec: spec)
                        .frame(width: spec.frame.w * unit - 6, height: spec.frame.h * unit - 6)
                        .offset(x: spec.frame.x * unit + 3, y: spec.frame.y * unit + 3)
                }

                tooltipOverlay(unit: unit, boardW: boardW, boardH: boardH)
            }
            .frame(width: boardW, height: boardH)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onPreferenceChange(HoveredControlKey.self) { newValue in
            withAnimation(.easeOut(duration: 0.14)) { hoveredControl = newValue }
        }
        .aspectRatio((layout.columns + 1) / (layout.rows + 1), contentMode: .fit)
        #if os(watchOS)
        .padding(7)          // fill most of the face, but keep off the bezel
        #else
        .padding(gap * 2)
        .padding(.top, 14)   // headroom so the underglow halo isn't clipped
        #endif
    }
}
