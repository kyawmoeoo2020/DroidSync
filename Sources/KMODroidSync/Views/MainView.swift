import SwiftUI

public struct MainView: View {
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
        } detail: {
            VStack(spacing: 0) {
                switch appState.currentSection {
                case .dashboard:
                    DashboardView(appState: appState)
                case .files, .photos, .downloads, .music:
                    FileBrowserView(appState: appState)
                case .apps:
                    AppManagerView(appState: appState)
                case .storageLens:
                    StorageLensView(appState: appState)
                case .wirelessPair:
                    WirelessPairView(appState: appState)
                }

                TransferQueueBar()
            }
            .navigationTitle(navigationTitle)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var navigationTitle: String {
        if let device = appState.selectedDevice {
            return "\(device.name) — KMO DroidSync"
        }
        return "KMO DroidSync"
    }
}
