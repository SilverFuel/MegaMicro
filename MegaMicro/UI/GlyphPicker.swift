import SwiftUI

/// A scrollable, graphical collection of key glyphs — a curated set of
/// SF Symbols matching what physical keycaps could show. Brand marks are
/// deliberately NOT offered here: those appear on a key only when an agent
/// actually lives there.
struct GlyphGrid: View {
    /// Current legend value ("sf:y", plain text, or nil).
    let current: String?
    let onSelect: (String?) -> Void

    private static let symbols = [
        "bolt", "checkmark.circle", "xmark.circle", "arrow.turn.up.right",
        "mic", "waveform", "play.fill", "stop.fill", "pause.fill",
        "arrow.triangle.branch", "arrow.triangle.2.circlepath", "arrow.up.circle",
        "terminal", "keyboard", "command", "cpu", "brain",
        "hammer", "wrench.adjustable", "gearshape", "paperplane",
        "folder", "doc.text", "magnifyingglass", "tray.full",
        "bell", "star", "heart", "flag", "bookmark", "tag",
        "lightbulb", "flame", "sparkles", "moon.zzz", "sun.max",
        "globe", "cloud", "cloud.bolt", "message", "phone",
        "camera", "music.note", "speaker.wave.2", "eye", "lock",
        "trash", "clock", "calendar", "chart.bar", "list.bullet",
    ]

    private let columns = [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, spacing: 6) {
                    cell(isSelected: current == nil || current?.isEmpty == true) {
                        Image(systemName: "slash.circle")
                            .foregroundStyle(.secondary)
                    } select: {
                        onSelect(nil)
                    }
                    .help("No glyph (show the mapped shortcut)")

                    ForEach(Self.symbols, id: \.self) { symbol in
                        cell(isSelected: current == "sf:\(symbol)") {
                            Image(systemName: symbol)
                                .font(.system(size: 14))
                        } select: {
                            onSelect("sf:\(symbol)")
                        }
                        .help(symbol)
                    }
                }
            }
            .padding(4)
        }
        .frame(minHeight: 120, maxHeight: 170)
    }

    private func cell(isSelected: Bool, @ViewBuilder content: () -> some View, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                                  lineWidth: isSelected ? 2 : 1))
                .overlay(content())
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

/// Standalone glyph picker sheet (right-click a key on the Agents board).
struct GlyphPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let control: ControlID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key Glyph")
                .font(.title3.bold())
            Text("Pick the glyph shown on this key — match whatever physical keycap you've installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GlyphGrid(current: appState.activeLayoutSettings.keyLegends[control]) { selection in
                var settings = appState.activeLayoutSettings
                if let selection {
                    settings.keyLegends[control] = selection
                } else {
                    settings.keyLegends.removeValue(forKey: control)
                }
                appState.activeLayoutSettings = settings
                dismiss()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
