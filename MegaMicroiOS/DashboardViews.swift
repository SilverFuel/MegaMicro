import SwiftUI

// MARK: Device tab — the live board (reuses the shared KeyboardView)

struct DeviceTab: View {
    let deviceName: String
    @Environment(DashboardModel.self) private var dashboard

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                KeyboardView()
                    .environment(\.agentBoardMode, true)
                    .frame(maxWidth: 460)
                    .padding(.horizontal)

                chipStrip
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(deviceName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Unassigned agents/workspaces — drag one onto a key to assign it (the
    /// drop routes a command back to the Mac).
    @ViewBuilder
    private var chipStrip: some View {
        let workspaces = dashboard.unassignedWorkspaces
        let sessions = dashboard.unassignedSessions
        if workspaces.isEmpty && sessions.isEmpty {
            Text("Everything is on a key. Drag keys to rearrange.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Drag onto a key").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workspaces) { ws in
                            chip(label: ws.displayName, brandAsset: "conductor")
                                .draggable("workspace:\(ws.id)")
                        }
                        ForEach(sessions, id: \.key) { session in
                            chip(label: dashboard.workContext(for: session) ?? session.agent ?? session.source,
                                 source: session.source)
                                .draggable("session:\(session.key)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func chip(label: String, brandAsset: String? = nil, source: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let brandAsset { BrandIcon(asset: brandAsset, size: 15) }
            else if let source { SourceIcon(source: source, size: 15) }
            Text(label).font(.subheadline).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.controlSurface))
        .overlay(Capsule().strokeBorder(.quaternary))
    }
}

// MARK: Activity tab — fleet card + feed (reads the shared DashboardModel)

struct ActivityTab: View {
    @Environment(DashboardModel.self) private var dashboard
    @State private var page = 0

    private let pageSize = 20

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(stateColor(dashboard.fleetNotification.state))
                            .frame(width: 11, height: 11).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dashboard.fleetNotification.headline).font(.headline)
                            Text(dashboard.fleetNotification.detail).foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Recent") {
                    ForEach(pagedItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            SourceIcon(source: item.source, size: 18).frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.agentName + " " + item.message).font(.subheadline.weight(.medium))
                                HStack(spacing: 5) {
                                    if let project = item.project { Text(project).fontWeight(.medium); Text("·") }
                                    if let slot = item.keySlot { Text("Key \(slot + 1)"); Text("·") }
                                    Text(item.at.formatted(.relative(presentation: .named)))
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle().fill(stateColor(item.state)).frame(width: 8, height: 8).padding(.top, 5)
                        }
                        .padding(.vertical, 2)
                    }
                    if dashboard.activityFeed.isEmpty {
                        Text("No activity yet").foregroundStyle(.secondary)
                    }
                }

                if pageCount > 1 {
                    Section {
                        HStack {
                            Button {
                                page = max(0, page - 1)
                            } label: {
                                Label("Newer", systemImage: "chevron.left")
                            }
                            .disabled(clampedPage == 0)

                            Spacer()
                            Text(rangeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()

                            Button {
                                page = min(pageCount - 1, page + 1)
                            } label: {
                                Label("Older", systemImage: "chevron.right")
                                    .labelStyle(.titleAndIcon)
                            }
                            .disabled(clampedPage == pageCount - 1)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("Activity")
            .onChange(of: dashboard.activityFeed.count) {
                page = clampedPage
            }
        }
    }

    private var pageCount: Int {
        max(1, (dashboard.activityFeed.count + pageSize - 1) / pageSize)
    }

    private var clampedPage: Int {
        min(max(0, page), pageCount - 1)
    }

    private var pagedItems: [ActivityFeedItem] {
        let start = clampedPage * pageSize
        let end = min(start + pageSize, dashboard.activityFeed.count)
        guard start < end else { return [] }
        return Array(dashboard.activityFeed[start..<end])
    }

    private var rangeLabel: String {
        let total = dashboard.activityFeed.count
        guard total > 0 else { return "" }
        let start = clampedPage * pageSize + 1
        let end = min(start + pageSize - 1, total)
        return "\(start)–\(end) of \(total)"
    }

    private func stateColor(_ state: AgentState) -> Color {
        let c = dashboard.rgbRules.spec(for: state).color
        return Color(hsv: HSV(h: c.h, s: c.s, v: 255))
    }
}

// MARK: Connect / pairing

struct ConnectView: View {
    @Bindable var client: SyncClient
    @State private var pairingCode = ""
    @State private var pairingTarget: SyncClient.Discovered?

    var body: some View {
        NavigationStack {
            List {
                if case .failed(let reason) = client.phase {
                    Section { Text(reason).foregroundStyle(.red) }
                }
                Section("MegaMicro on your network") {
                    if client.discovered.isEmpty {
                        HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                    }
                    ForEach(client.discovered) { device in
                        Button {
                            if client.hasPairing(for: device) {
                                client.connect(to: device)
                            } else {
                                pairingTarget = device
                            }
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(device.name)
                                Spacer()
                                if client.hasPairing(for: device) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("Make sure your Mac and this device are on the same Wi-Fi network.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect")
            .sheet(item: $pairingTarget) { device in
                PairingSheet(deviceName: device.name, code: $pairingCode) {
                    client.connect(to: device, pairingCode: pairingCode)
                    pairingTarget = nil
                    pairingCode = ""
                }
            }
        }
    }
}

struct PairingSheet: View {
    let deviceName: String
    @Binding var code: String
    let onPair: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.laptopcomputer").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Pair with \(deviceName)").font(.title2.weight(.semibold))
                Text("Open MegaMicro on your Mac, start pairing, and enter the 6-digit code it shows.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                TextField("000000", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 200)
                Button("Pair", action: onPair)
                    .buttonStyle(.borderedProminent)
                    .disabled(code.count != 6)
                Spacer()
            }
            .padding()
        }
    }
}
