import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var appState: AppState

    public var body: some View {
        VStack(spacing: 0) {
            // App Branding Header
            HStack(spacing: 10) {
                if let logo = appLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("DroidSync")
                        .font(.system(size: 14, weight: .bold))
                    Text("by Kyaw Moe Oo")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

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

            Divider()

            // Footer
            HStack {
                Text("DroidSync v1.0.0")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: openAbout) {
                    Text("About")
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 230)
    }

    private var appLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                     Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "DroidSync_Logo", withExtension: "png") ??
                     Bundle.module.url(forResource: "DroidSync_Logo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }

    private func openAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "DroidSync",
            .version: "1.0.0",
            .credits: NSAttributedString(
                string: "Developed by Kyaw Moe Oo\n\nHigh-performance native Android sync tool for macOS",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        ]
        if let icon = appLogo {
            options[.applicationIcon] = icon
        }

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
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
            Image(systemName: device.connectionType == .wifi ? "wifi" : "cable.connector")
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
