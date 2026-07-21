import WidgetKit
import SwiftUI

/// A watch-face complication that launches MegaMicro when tapped — the
/// hot-corner glance into your agents.
@main
struct MegaMicroComplicationBundle: WidgetBundle {
    var body: some Widget { MegaMicroComplication() }
}

struct MMEntry: TimelineEntry {
    let date: Date
}

struct MMProvider: TimelineProvider {
    func placeholder(in context: Context) -> MMEntry { MMEntry(date: .distantPast) }
    func getSnapshot(in context: Context, completion: @escaping (MMEntry) -> Void) {
        completion(MMEntry(date: .distantPast))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MMEntry>) -> Void) {
        completion(Timeline(entries: [MMEntry(date: .distantPast)], policy: .never))
    }
}

struct MegaMicroComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MegaMicroComplication", provider: MMProvider()) { _ in
            MegaMicroComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("MegaMicro")
        .description("Open MegaMicro from your watch face.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryCorner, .accessoryInline]
        #else
        [.accessoryCircular, .accessoryInline]
        #endif
    }
}

private struct MegaMicroComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryInline {
                Label("MegaMicro", systemImage: "keyboard")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: family == .accessoryCorner ? 18 : 16,
                                      weight: .bold))
                        .widgetAccentable()
                }
                // On corner-capable faces this becomes the curved text around
                // the icon, making the launcher recognizable in the hot corner.
                .widgetLabel { Text("MegaMicro") }
            }
        }
        .accessibilityLabel("Open MegaMicro")
    }
}
