import SwiftUI
import UIKit

@main
struct MegaMicroiOSApp: App {
    @State private var client = SyncClient(clientName: UIDevice.current.name)

    var body: some Scene {
        WindowGroup {
            RootView(client: client)
                .environment(client.dashboard)
                .preferredColorScheme(.dark)   // the white device pops on dark
                .onAppear { client.startBrowsing() }
        }
    }
}

/// Shows discovery/pairing until connected, then the two-tab dashboard.
struct RootView: View {
    @Bindable var client: SyncClient

    var body: some View {
        switch client.phase {
        case .connected:
            DashboardTabs(client: client)
        default:
            ConnectView(client: client)
        }
    }
}

struct DashboardTabs: View {
    @Bindable var client: SyncClient

    var body: some View {
        TabView {
            DeviceTab(deviceName: client.connectedName ?? "MegaMicro")
                .tabItem { Label("Device", systemImage: "keyboard") }
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }
        }
    }
}
