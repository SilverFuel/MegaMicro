import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Keyboard layout management, embedded at the bottom of the Keyboard pane:
/// the built-in Codex Micro plus user-imported boards (VIA/KLE JSON).
struct LayoutsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layouts").font(.headline)
                Spacer()
                Button {
                    importLayout()
                } label: {
                    Label("Import Layout…", systemImage: "plus")
                }
                .font(.callout)
            }
            ForEach(appState.allLayouts) { layout in
                row(layout)
            }
            Text("Import a VIA keyboard definition (usevia.app) or KLE JSON. Key bindings, labels, and agents are stored per layout. Imported boards get keys only for now.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(6)
    }

    @ViewBuilder
    private func row(_ layout: KeyboardLayout) -> some View {
        @Bindable var state = appState
        let isBuiltin = layout.id == CodexMicroLayout.layout.id
        let isActive = layout.id == appState.config.activeLayoutID
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(layout.name).font(.callout.weight(.medium))
                    if isBuiltin {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundStyle(.green)
                    }
                }
                Text("\(layout.controls.filter { $0.kind == .key }.count) keys · \(layout.ledCount) LEDs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button("Activate") {
                    state.config.activeLayoutID = layout.id
                }
                .font(.callout)
            }
        }
        .contextMenu {
            Button("Activate") { state.config.activeLayoutID = layout.id }
            if !isBuiltin {
                Button("Delete", role: .destructive) { appState.deleteLayout(id: layout.id) }
            }
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose a VIA keyboard definition or KLE layout JSON"
        if panel.runModal() == .OK, let url = panel.url {
            appState.importLayout(from: url)
        }
    }
}
