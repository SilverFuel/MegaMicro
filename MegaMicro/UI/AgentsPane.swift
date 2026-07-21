import SwiftUI
import AppKit

/// Key-centric agent assignment: drag unassigned agent chips onto the
/// keyboard. One key = one agent.
struct AgentsPane: View {
    @Environment(AppState.self) private var appState

    private enum FleetFilter: String, CaseIterable, Hashable {
        case all = "All"
        case active = "Active"
        case waiting = "Waiting"
        case finished = "Finished"
        case errors = "Errors"
    }
    @State private var fleetFilter: FleetFilter = .all
    @State private var projectFilter = "All Projects"

    var body: some View {
        Form {
            Section {
                Text("Assign each running AI agent or Conductor workspace to a physical key. The key then shows that agent’s live status, and pressing it jumps back to the agent.")
                    .font(.callout)
            }
            if appState.demoModeEnabled {
                Section {
                    HStack {
                        Label("Demo mode — all agents and activity are simulated", systemImage: "film.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Next Cast") { appState.nextDemoCast() }
                        Button("Stop") { appState.stopDemoMode() }
                    }
                }
            }
            Section {
                HStack {
                    Picker("Fleet", selection: $fleetFilter) {
                        ForEach(FleetFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    Menu(projectFilter) {
                        Button("All Projects") { projectFilter = "All Projects" }
                        Divider()
                        ForEach(projectNames, id: \.self) { project in
                            Button(project) { projectFilter = project }
                        }
                    }
                    .frame(minWidth: 130)
                }
            } header: {
                Text("Fleet Filters")
            }

            boardSection
        }
        .formStyle(.grouped)
    }

    // MARK: Board tab

    @ViewBuilder
    private var boardSection: some View {
        Section {
            if unassignedWorkspaces.isEmpty && unassignedSessions.isEmpty {
                Text(fleetFilter == .all && projectFilter == "All Projects"
                     ? "Everything is assigned. Drag Auto onto a key to free it, or Off to disable it."
                     : "No unassigned agents match these fleet filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                // Utility chips stay first, followed by every unassigned
                // workspace/agent. The adaptive grid wraps instead of
                // hiding agents behind horizontal scrolling.
                utilityChip("Auto", systemImage: "arrow.triangle.2.circlepath", payload: "auto")
                utilityChip("Off", systemImage: "moon.zzz", payload: "off")
                ForEach(unassignedWorkspaces) { workspace in
                    agentChip("\(workspace.project) · \(workspace.displayName)", brandAsset: "conductor",
                              payload: "workspace:\(workspace.id)",
                              help: "Conductor workspace\nProject: \(workspace.project)\nWorkspace: \(workspace.displayName)\n\(workspace.path)",
                              onDismiss: { appState.dismissAgent(payload: "workspace:\(workspace.id)") })
                }
                ForEach(unassignedSessions, id: \.key) { session in
                    agentChip(session.agent ?? (session.cwd as NSString?)?.lastPathComponent ?? session.session,
                              source: session.source,
                              stateDot: Color(hsv: stateColor(session.state)),
                              payload: "session:\(session.key)",
                              help: appState.agentDetailText(session),
                              onDismiss: { appState.dismissAgent(payload: "session:\(session.key)") })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            // Drag a key's agent up here to unassign it (it returns as a chip).
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first, payload.hasPrefix("move:"),
                      let slot = Int(payload.dropFirst("move:".count)) else { return false }
                appState.unassignKey(slot)
                return true
            }
            HStack {
                Spacer()
                KeyboardView()
                    .environment(\.agentBoardMode, true)
                    .frame(maxWidth: 340, maxHeight: 320)
                Spacer()
            }
        } header: {
            HStack {
                Text("Drag an active agent onto a key")
                Spacer()
                Button("Unassign all agents from keys") {
                    appState.unassignAllKeys()
                }
                .font(.callout)
            }
        } footer: {
            Text("""
            Chips are agents waiting for a key: live sessions from any connected tool \
            (Claude Code, Codex, Antigravity, OpenCode, Cursor, or anything reporting to the webhook) plus \
            Conductor workspaces on disk. A chip disappears once it is assigned; its icon \
            and live state appear directly on the key.
            """)
            .font(.caption)
        }
    }

    // MARK: List tab

    private var keysSection: some View {
        Section {
            ForEach(appState.ledKeySlots, id: \.self) { slot in
                keyRow(slot)
            }
        } header: {
            Text("Keys")
        } footer: {
            Text("Keys light only for their assigned workspace or folder. Unassigned agents wait in the Board tab\u{2019}s chip strip until you place them.")
                .font(.caption)
        }
    }

    private var liveAgentsSection: some View {
        Section("Live agents") {
            let sessions = appState.sessionStore.sessions
            if sessions.isEmpty {
                Text("No agents reporting right now.")
                    .foregroundStyle(.secondary)
            }
            ForEach(liveSessions, id: \.key) { session in
                HStack {
                    SourceIcon(source: session.source, size: 16)
                    VStack(alignment: .leading) {
                        Text(session.agent ?? (session.cwd as NSString?)?.lastPathComponent ?? session.session)
                            .font(.headline)
                        Text([session.source, session.model, session.state.wireName]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(homeDescription(for: session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        appState.sessionStore.remove(sessionKey: session.key)
                        appState.log("dismissed agent \(session.session)")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this agent (frees its key)")
                }
                .help(appState.agentDetailText(session))
            }
        }
    }

    // MARK: Chips

    private var liveSessions: [AgentSession] {
        appState.sessionStore.sessions.values
            .filter { !appState.isExcludedFromFleet($0) }
            .filter(matchesFilters)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var projectNames: [String] {
        let sessionProjects = appState.sessionStore.sessions.values.compactMap {
            appState.projectName(for: $0)
        }
        return Set(sessionProjects + appState.workspaces.map(\.project)).sorted()
    }

    private func matchesFilters(_ session: AgentSession) -> Bool {
        let stateMatches: Bool = switch fleetFilter {
        case .all: true
        case .active: session.state == .thinking || session.state == .coding
        case .waiting: session.state == .waiting
        case .finished: session.state == .success || session.state == .idle
        case .errors: session.state == .error
        }
        let projectMatches = projectFilter == "All Projects"
            || appState.projectName(for: session) == projectFilter
        return stateMatches && projectMatches
    }

    /// Workspaces not yet bound to any key.
    private var unassignedWorkspaces: [ConductorWorkspace] {
        // Conductor folders have no live state telemetry of their own. Show
        // them in the complete inventory, but don't imply that they match a
        // state filter such as Active or Errors.
        guard fleetFilter == .all else { return [] }
        let bound = Set(appState.activeLayoutSettings.keyBindings.values.compactMap { binding -> String? in
            if case .workspace(let id) = binding { return id }
            return nil
        })
        return appState.workspaces.filter { workspace in
            !bound.contains(workspace.id)
                && !appState.isWorkspaceExcluded(workspace)
                && (projectFilter == "All Projects" || workspace.project == projectFilter)
        }
    }

    /// Sessions whose folder isn't already covered by a bound key.
    private var unassignedSessions: [AgentSession] {
        liveSessions.filter { !isCovered($0) }
    }

    private func isCovered(_ session: AgentSession) -> Bool {
        guard let cwd = session.cwd else { return false }
        for binding in appState.activeLayoutSettings.keyBindings.values {
            switch binding {
            case .workspace(let id):
                let path = appState.workspacesRoot + "/" + id
                if cwd == path || cwd.hasPrefix(path + "/") { return true }
            case .path(let path):
                if cwd == path || cwd.hasPrefix(path + "/") { return true }
            case .off:
                continue
            }
        }
        return false
    }

    private func stateColor(_ state: AgentState) -> HSV {
        let color = appState.activeProfile.rgbRules.spec(for: state).color
        return HSV(h: color.h, s: color.s, v: 255)
    }

    private func utilityChip(_ label: String, systemImage: String, payload: String) -> some View {
        chipShell(payload: payload) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(label).font(.callout).lineLimit(1)
        }
    }

    private func agentChip(_ label: String, brandAsset: String? = nil, source: String? = nil,
                           stateDot: Color? = nil, payload: String, help: String? = nil,
                           onDismiss: (() -> Void)? = nil) -> some View {
        chipShell(payload: payload, help: help, onDismiss: onDismiss) {
            if let brandAsset {
                BrandIcon(asset: brandAsset, size: 13)
            } else if let source {
                SourceIcon(source: source, size: 13)
            }
            Text(label).font(.callout).lineLimit(1)
            if let stateDot {
                Circle().fill(stateDot).frame(width: 6, height: 6)
            }
        }
    }

    private func chipShell(payload: String, help: String? = nil,
                           onDismiss: (() -> Void)? = nil,
                           @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 5) {
            content()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from monitoring")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().strokeBorder(.quaternary))
        .draggable(payload)
        .help(help.map { $0 + "\nDrag onto a key · ✕ to stop monitoring" } ?? "Drag onto a key")
    }

    // MARK: Key row

    @ViewBuilder
    private func keyRow(_ slot: Int) -> some View {
        HStack(spacing: 10) {
            ledDot(slot)
            VStack(alignment: .leading) {
                Text(keyName(slot)).font(.headline)
                Text(occupantDescription(slot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            bindingMenu(slot)
        }
    }

    private func bindingMenu(_ slot: Int) -> some View {
        @Bindable var state = appState
        return Menu(bindingLabel(slot)) {
            Button("Auto (any agent)") { state.activeLayoutSettings.keyBindings.removeValue(forKey: slot) }
            Button("Off") { state.activeLayoutSettings.keyBindings[slot] = .off }
            if !appState.workspaces.isEmpty {
                Divider()
                ForEach(appState.workspaces) { workspace in
                    Button("Conductor: \(workspace.project) · \(workspace.displayName)") {
                        for (s, b) in state.activeLayoutSettings.keyBindings {
                            if case .workspace(workspace.id) = b { state.activeLayoutSettings.keyBindings.removeValue(forKey: s) }
                        }
                        state.activeLayoutSettings.keyBindings[slot] = .workspace(workspace.id)
                    }
                }
            }
            Divider()
            Button("Choose Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Assign to Key"
                if panel.runModal() == .OK, let url = panel.url {
                    state.activeLayoutSettings.keyBindings[slot] = .path(url.path)
                }
            }
        }
        .frame(width: 190)
    }

    // MARK: Descriptions

    private func keyName(_ slot: Int) -> String {
        let label = appState.activeLayoutSettings.keyLegends[.key(slot)]
        return "Key \(slot + 1)" + (label.map { "  \($0)" } ?? "")
    }

    private func bindingLabel(_ slot: Int) -> String {
        switch appState.activeLayoutSettings.keyBindings[slot] {
        case nil: "Auto"
        case .off: "Off"
        case .workspace(let id): appState.workspaceDisplayName(forID: id)
        case .path(let path): appState.folderAgentLabel(forPath: path)
        }
    }

    private func occupantDescription(_ slot: Int) -> String {
        switch appState.activeLayoutSettings.keyBindings[slot] {
        case .off:
            return "disabled"
        case .workspace(let id):
            return "Conductor · \(appState.workspaceDisplayName(forID: id))"
        case .path(let path):
            return path
        case nil:
            return "free — drag an agent here"
        }
    }

    private func homeDescription(for session: AgentSession) -> String {
        if let cwd = session.cwd {
            for (slot, binding) in appState.activeLayoutSettings.keyBindings {
                switch binding {
                case .workspace(let id) where cwd.contains("/conductor/workspaces/\(id)"):
                    return "→ \(keyName(slot))"
                case .path(let path) where cwd == path || cwd.hasPrefix(path + "/"):
                    return "→ \(keyName(slot))"
                default:
                    continue
                }
            }
        }
        return "unassigned — drag onto a key"
    }

    private func ledDot(_ slot: Int) -> some View {
        let color: Color
        if let led = appState.layout.control(.key(slot))?.ledIndex,
           led < appState.currentFrame.perLED.count {
            let hsv = appState.currentFrame.perLED[led]
            color = hsv.v > 0 ? Color(hsv: HSV(h: hsv.h, s: hsv.s, v: 255)) : .secondary.opacity(0.3)
        } else {
            color = .secondary.opacity(0.3)
        }
        return Circle().fill(color).frame(width: 10, height: 10)
    }
}
