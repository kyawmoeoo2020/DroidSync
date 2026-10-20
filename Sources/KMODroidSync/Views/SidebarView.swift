import SwiftUI

public struct SidebarView: View {
    @ObservedObject var appState: AppState

    public var body: some View {
        List {
            Section("Connected Devices") {
                if appState.connectedDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Waiting for device...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("Connect phone via USB with USB Debugging enabled, or pair via Wi-Fi.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(appState.connectedDevices) { device in
                        DeviceRow(device: device, isSelected: appState.selectedDevice?.id == device.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedDevice = device
                            }
                    }
                }
            }

            Section("Device Management") {
                SidebarNavItem(
                    title: "Overview",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    isSelected: appState.currentSection == .dashboard
                ) {
                    appState.currentSection = .dashboard
                }

                SidebarNavItem(
                    title: "Internal Storage",
                    icon: "folder.fill",
                    isSelected: isCurrentPath("/sdcard")
                ) {
                    appState.navigateTo(path: "/sdcard")
                }

                SidebarNavItem(
                    title: "Camera & Photos",
                    icon: "photo.on.rectangle.angled",
                    isSelected: isCurrentPath("/sdcard/DCIM")
                ) {
                    appState.navigateTo(path: "/sdcard/DCIM")
                }

                SidebarNavItem(
                    title: "Downloads",
                    icon: "arrow.down.circle.fill",
                    isSelected: isCurrentPath("/sdcard/Download")
                ) {
                    appState.navigateTo(path: "/sdcard/Download")
                }

                SidebarNavItem(
                    title: "Music",
                    icon: "music.note.list",
                    isSelected: isCurrentPath("/sdcard/Music")
                ) {
                    appState.navigateTo(path: "/sdcard/Music")
                }
            }

            Section("Tools") {
                SidebarNavItem(
                    title: "App Manager",
                    icon: "square.grid.2x2.fill",
                    isSelected: appState.currentSection == .apps
                ) {
                    appState.currentSection = .apps
                    appState.loadPackages()
                }

                SidebarNavItem(
                    title: "Storage Lens",
                    icon: "chart.pie.fill",
                    isSelected: appState.currentSection == .storageLens
                ) {
                    appState.currentSection = .storageLens
                }

                SidebarNavItem(
                    title: "Wireless Pairing",
                    icon: "wifi.circle.fill",
                    isSelected: appState.currentSection == .wirelessPair
                ) {
                    appState.currentSection = .wirelessPair
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 230)
    }

    private func isCurrentPath(_ path: String) -> Bool {
        if case .files(let current) = appState.currentSection {
            return current == path
        }
        return false
    }
}

private struct DeviceRow: View {
    let device: Device
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.platform == .ios ? "apple.logo" : (device.connectionType == .wifi ? "wifi" : "cable.connector"))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(device.osVersion)
                    Text("•")
                    Text("\(device.batteryLevel)%")
                    if device.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }
}

private struct SidebarNavItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .frame(width: 18)
                Text(title)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .fontWeight(isSelected ? .medium : .regular)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
