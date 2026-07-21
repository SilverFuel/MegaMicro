import SwiftUI

/// Structured content for the floating key tooltip — a titled card with an
/// optional colored state pill, label/value rows, and a footer hint. Replaces
/// the plain system `.help()` bubble for the on-board keys.
struct TooltipData: Equatable {
    var title: String
    var stateText: String?
    var accent: Color?
    var rows: [Row]
    var footer: String?

    struct Row: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }
}

/// Which control (if any) is currently hovered long enough to show its card.
/// Reduced up the view tree from the individual caps.
struct HoveredControlKey: PreferenceKey {
    static let defaultValue: ControlID? = nil
    static func reduce(value: inout ControlID?, nextValue: () -> ControlID?) {
        if let next = nextValue() { value = next }
    }
}

/// Measured size of the rendered card, so the board can place it precisely
/// above (or below) the hovered key.
struct TooltipSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The floating card itself: frosted background, hairline border, soft shadow,
/// a state-colored accent dot + pill. Non-interactive.
struct TooltipCard: View {
    let data: TooltipData

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                if let accent = data.accent {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: accent.opacity(0.8), radius: 4)
                }
                Text(data.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let stateText = data.stateText {
                    Text(stateText.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((data.accent ?? .secondary).opacity(0.18)))
                        .foregroundStyle(data.accent ?? .secondary)
                }
            }

            if !data.rows.isEmpty {
                Divider().opacity(0.5)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(data.rows) { row in
                        GridRow {
                            Text(row.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.72))
                                .gridColumnAlignment(.leading)
                            Text(row.value)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
            }

            if let footer = data.footer {
                Text(footer)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
        .fixedSize()
    }
}
