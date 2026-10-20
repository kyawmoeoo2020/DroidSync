import SwiftUI
import UniformTypeIdentifiers

public struct AppManagerView: View {
    @ObservedObject var appState: AppState
    @State private var searchPackageText = ""
    @State private var selectedPackage: String?
    @State private var isTargetedForApkDrop = false
    @State private var actionMessage = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            HStack(spacing: 12) {
                Text("Installed Apps")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search packages...", text: $searchPackageText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(width: 160)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                Button(action: promptInstallApk) {
                    Label("Install APK...", systemImage: "plus.circle")
                }

                Button(action: {
                    appState.loadPackages()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if !actionMessage.isEmpty {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(actionMessage)
                        .font(.subheadline)
                    Spacer()
                    Button("Dismiss") { actionMessage = "" }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
            }

            if appState.isLoadingPackages {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading installed packages...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPackages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No 3rd-party apps found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Drag .apk files here to install them onto your phone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredPackages, id: \.self, selection: $selectedPackage) { pkg in
                    HStack(spacing: 12) {
                        Image(systemName: "app.badge.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pkg)
                                .font(.body)
                                .fontWeight(.medium)
                        }

                        Spacer()

                        Button(role: .destructive, action: {
                            uninstallPackage(pkg)
                        }) {
                            Image(systemName: "trash")
                        }
                        .help("Uninstall App")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForApkDrop) { providers in
            handleApkDrop(providers: providers)
        }
        .overlay(
            isTargetedForApkDrop ?
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 3)
                    .background(Color.green.opacity(0.1))
                : nil
        )
    }

    private var filteredPackages: [String] {
        if searchPackageText.isEmpty {
            return appState.installedPackages
        }
        return appState.installedPackages.filter {
            $0.localizedCaseInsensitiveContains(searchPackageText)
        }
    }

    private func promptInstallApk() {
        guard let device = appState.selectedDevice else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "apk")].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            installApkFile(url: url, serial: device.id)
        }
    }

    private func handleApkDrop(providers: [NSItemProvider]) -> Bool {
        guard let device = appState.selectedDevice else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    if url.pathExtension.lowercased() == "apk" {
                        DispatchQueue.main.async {
                            self.installApkFile(url: url, serial: device.id)
                        }
                    }
                } else if let url = item as? URL, url.pathExtension.lowercased() == "apk" {
                    DispatchQueue.main.async {
                        self.installApkFile(url: url, serial: device.id)
                    }
                }
            }
        }
        return true
    }

    private func installApkFile(url: URL, serial: String) {
        actionMessage = "Installing \(url.lastPathComponent)..."
        Task {
            do {
                let res = try await ADBManager.shared.installApk(serial: serial, apkURL: url)
                await MainActor.run {
                    actionMessage = "Installed: \(res.trimmingCharacters(in: .whitespacesAndNewlines))"
                    appState.loadPackages()
                }
            } catch {
                await MainActor.run {
                    actionMessage = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func uninstallPackage(_ pkg: String) {
        guard let device = appState.selectedDevice else { return }
        actionMessage = "Uninstalling \(pkg)..."
        Task {
            _ = try? await ADBManager.shared.executeAdb(["-s", device.id, "uninstall", pkg])
            await MainActor.run {
                actionMessage = "Uninstalled \(pkg)"
                appState.loadPackages()
            }
        }
    }
}
