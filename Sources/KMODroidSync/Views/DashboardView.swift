import SwiftUI

public struct DashboardView: View {
    @ObservedObject var appState: AppState

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let device = appState.selectedDevice {
                    // Header Card
                    HStack(alignment: .center, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Image(systemName: "iphone.gen3")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(device.name)
                                .font(.title)
                                .fontWeight(.bold)

                            HStack(spacing: 8) {
                                Label(device.osVersion, systemImage: "gearshape.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .foregroundColor(.secondary)

                                Label(device.connectionType.rawValue, systemImage: device.connectionType == .wifi ? "wifi" : "cable.connector")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .foregroundColor(.secondary)

                                Text("ID: \(device.id)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(action: {
                            appState.refreshDevices()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        // Storage Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Storage", systemImage: "internaldrive.fill")
                                    .font(.headline)
                                Spacer()
                                Text("\(device.storage.formattedUsed) / \(device.storage.formattedTotal)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            // Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 12)

                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(device.storage.usedPercentage), height: 12)
                                }
                            }
                            .frame(height: 12)

                            HStack {
                                Text("\(device.storage.formattedFree) Available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f%% Used", device.storage.usedPercentage * 100))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)

                        // Battery Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Battery Health", systemImage: "battery.100")
                                    .font(.headline)
                                Spacer()
                                Text("\(device.batteryLevel)%")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(device.batteryLevel > 20 ? .green : .red)
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Status")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        if device.isCharging {
                                            Image(systemName: "bolt.fill")
                                                .foregroundColor(.green)
                                            Text("Charging")
                                        } else {
                                            Text("On Battery")
                                        }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Temperature")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f°C", device.batteryTempCelsius))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }

                    // Quick Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Actions")
                            .font(.headline)

                        HStack(spacing: 12) {
                            QuickActionButton(
                                title: "Browse Files",
                                subtitle: "Explore /sdcard",
                                icon: "folder.fill",
                                color: .blue
                            ) {
                                appState.navigateTo(path: "/sdcard")
                            }

                            QuickActionButton(
                                title: "Camera DCIM",
                                subtitle: "Photos & Videos",
                                icon: "photo.fill",
                                color: .purple
                            ) {
                                appState.navigateTo(path: "/sdcard/DCIM")
                            }

                            QuickActionButton(
                                title: "App Manager",
                                subtitle: "Install & Manage APKs",
                                icon: "square.grid.2x2.fill",
                                color: .green
                            ) {
                                appState.currentSection = .apps
                                appState.loadPackages()
                            }

                            QuickActionButton(
                                title: "Wireless Mode",
                                subtitle: "Connect via Wi-Fi",
                                icon: "wifi",
                                color: .orange
                            ) {
                                appState.currentSection = .wirelessPair
                            }
                        }
                    }
                } else {
                    // No Device Selected State
                    VStack(spacing: 16) {
                        Image(systemName: "cable.connector.horizontal")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.secondary)

                        Text("No Android Device Connected")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Connect your Android phone using a USB cable and ensure **USB Debugging** is turned on in Developer Options.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 450)

                        Button(action: {
                            appState.refreshDevices()
                        }) {
                            Label("Scan for Devices", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 350)
                }
            }
            .padding(24)
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
