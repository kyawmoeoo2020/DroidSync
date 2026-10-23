import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct AppManagerView: View {
    @ObservedObject var appState: AppState
    @State private var searchPackageText = ""
    @State private var selectedAppIds: Set<String> = []
    @State private var isTargetedForApkDrop = false
    @State private var actionMessage = ""
    @State private var isActionError = false
    @State private var isPerformingAction = false

    private var selectedAppsList: [AppInfo] {
        filteredApps.filter { selectedAppIds.contains($0.id) }
    }

    // App Details Sheet
    @State private var inspectingApp: AppInfo?
    @State private var appDetails: AppDetailedInfo?
    @State private var isLoadingDetails = false

    // Confirmation Alerts
    @State private var appToUninstall: AppInfo?
    @State private var showUninstallAlert = false
    @State private var appToClearData: AppInfo?
    @State private var showClearDataAlert = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Installed Apps")
                                .font(.title2)
                                .fontWeight(.bold)

                            if !appState.installedApps.isEmpty {
                                Text("\(filteredApps.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("Manage, backup, freeze, launch, and install APKs on your Android phone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search apps or packages...", text: $searchPackageText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .frame(width: 170)
                        if !searchPackageText.isEmpty {
                            Button(action: { searchPackageText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)

                    // Install APK Button
                    Button(action: promptInstallApk) {
                        Label("Install APK / XAPK...", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Install .apk or .xapk / split app bundles on your Android device")
                    .disabled(isPerformingAction)

                    // Refresh Button
                    Button(action: {
                        appState.loadPackages()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Apps")
                    .disabled(appState.isLoadingPackages || isPerformingAction)
                }

                // Filter Tabs Bar & Multi-selection Actions
                HStack(spacing: 8) {
                    ForEach(AppFilterType.allCases) { filter in
                        Button(action: {
                            appState.loadPackages(filter: filter)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: filter.systemImage)
                                    .font(.system(size: 11))
                                Text(filter.rawValue)
                                    .font(.system(size: 12, weight: appState.appFilter == filter ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(appState.appFilter == filter ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundColor(appState.appFilter == filter ? .accentColor : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()

                    if !selectedAppIds.isEmpty {
                        HStack(spacing: 8) {
                            Text("\(selectedAppIds.count) selected")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Button(action: exportSelectedApks) {
                                Label("Export \(selectedAppIds.count > 1 ? "\(selectedAppIds.count) APKs" : "APK")...", systemImage: "arrow.down.doc.fill")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(selectedAppIds.count == filteredApps.count ? "Deselect All" : "Select All") {
                                if selectedAppIds.count == filteredApps.count {
                                    selectedAppIds.removeAll()
                                } else {
                                    selectedAppIds = Set(filteredApps.map(\.id))
                                }
                            }
                            .controlSize(.small)

                            Button(action: { selectedAppIds.removeAll() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Deselect all")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Status / Action Banner
            if !actionMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: isActionError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(isActionError ? .red : .green)
                    Text(actionMessage)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Dismiss") {
                        actionMessage = ""
                    }
                    .font(.caption)
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isActionError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))

                Divider()
            }

            // Main App Content
            if appState.isLoadingPackages {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading applications from device...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No applications found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Drag and drop any .apk file from your Mac here to install it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps, id: \.id, selection: $selectedAppIds) { app in
                    AppRowView(
                        app: app,
                        isSelected: selectedAppIds.contains(app.id),
                        onLaunch: { launchApp(app) },
                        onForceStop: { forceStopApp(app) },
                        onBackupApk: { backupApk(app) },
                        onInspect: { inspectApp(app) },
                        onToggleEnabled: { toggleAppEnabled(app) },
                        onClearDataPrompt: { promptClearData(app) },
                        onUninstallPrompt: { promptUninstall(app) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if selectedAppIds.contains(app.id) {
                                selectedAppIds.remove(app.id)
                            } else {
                                selectedAppIds.insert(app.id)
                            }
                        } else if NSEvent.modifierFlags.contains(.shift), let lastId = selectedAppIds.first,
                                  let lastIdx = filteredApps.firstIndex(where: { $0.id == lastId }),
                                  let curIdx = filteredApps.firstIndex(where: { $0.id == app.id }) {
                            let start = min(lastIdx, curIdx)
                            let end = max(lastIdx, curIdx)
                            for idx in start...end {
                                selectedAppIds.insert(filteredApps[idx].id)
                            }
                        } else {
                            selectedAppIds = [app.id]
                        }
                    }
                    .contextMenu {
                        if selectedAppIds.count > 1 {
                            Button("Export \(selectedAppIds.count) Selected APKs...") {
                                exportSelectedApks()
                            }
                            Divider()
                        }
                        Button("Launch on Phone") { launchApp(app) }
                        Button("Force Stop") { forceStopApp(app) }
                        Divider()
                        Button("Backup APK to Mac...") { backupApk(app) }
                        Button(app.isEnabled ? "Disable App (Freeze)" : "Enable App (Unfreeze)") {
                            toggleAppEnabled(app)
                        }
                        Button("Clear Data & Cache...") { promptClearData(app) }
                        Divider()
                        Button("View App Info & Permissions") { inspectApp(app) }
                        Button("Copy Package Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(app.packageName, forType: .string)
                        }
                        Divider()
                        Button("Uninstall App...", role: .destructive) {
                            promptUninstall(app)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        // Drag and drop APK installation
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForApkDrop) { providers in
            handleApkDrop(providers: providers)
        }
        .overlay(
            isTargetedForApkDrop ?
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.12))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.app.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.accentColor)
                            Text("Drop APK to Install on Device")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        }
                    )
                : nil
        )
        // Detailed Inspector Sheet
        .sheet(item: $inspectingApp) { app in
            AppInspectorSheet(app: app, details: appDetails, isLoading: isLoadingDetails) {
                inspectingApp = nil
                appDetails = nil
            }
        }
        // Uninstall Confirmation Alert
        .alert("Uninstall \(appToUninstall?.displayName ?? "App")?", isPresented: $showUninstallAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                if let app = appToUninstall {
                    executeUninstall(app)
                }
            }
        } message: {
            if let app = appToUninstall {
                Text("This will remove '\(app.packageName)' and all of its associated data from the connected phone.")
            }
        }
        // Clear Data Confirmation Alert
        .alert("Clear Data for \(appToClearData?.displayName ?? "App")?", isPresented: $showClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Data", role: .destructive) {
                if let app = appToClearData {
                    executeClearData(app)
                }
            }
        } message: {
            if let app = appToClearData {
                Text("This will permanently delete databases, settings, and cache files for '\(app.packageName)'.")
            }
        }
        .onAppear {
            if appState.installedApps.isEmpty {
                appState.loadPackages()
            }
        }
    }

    private var filteredApps: [AppInfo] {
        if searchPackageText.isEmpty {
            return appState.installedApps
        }
        return appState.installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchPackageText) ||
            $0.packageName.localizedCaseInsensitiveContains(searchPackageText)
        }
    }

    // MARK: - App Operations

    private func launchApp(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        actionMessage = "Launching \(app.displayName) on device..."
        isActionError = false
        Task {
            do {
                _ = try await ADBManager.shared.launchApp(serial: device.id, packageName: app.packageName)
                await MainActor.run {
                    self.actionMessage = "Launched \(app.displayName) successfully"
                    self.isActionError = false
                }
            } catch {
                await MainActor.run {
                    self.actionMessage = "Failed to launch: \(error.localizedDescription)"
                    self.isActionError = true
                }
            }
        }
    }

    private func forceStopApp(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        actionMessage = "Stopping \(app.displayName)..."
        isActionError = false
        Task {
            do {
                try await ADBManager.shared.forceStopApp(serial: device.id, packageName: app.packageName)
                await MainActor.run {
                    self.actionMessage = "\(app.displayName) stopped"
                    self.isActionError = false
                }
            } catch {
                await MainActor.run {
                    self.actionMessage = "Failed to stop: \(error.localizedDescription)"
                    self.isActionError = true
                }
            }
        }
    }

    private func toggleAppEnabled(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        let targetEnable = !app.isEnabled
        actionMessage = targetEnable ? "Enabling \(app.displayName)..." : "Freezing \(app.displayName)..."
        isActionError = false
        Task {
            do {
                _ = try await ADBManager.shared.setAppEnabled(serial: device.id, packageName: app.packageName, enable: targetEnable)
                await MainActor.run {
                    self.actionMessage = targetEnable ? "\(app.displayName) enabled" : "\(app.displayName) frozen"
                    self.isActionError = false
                    self.appState.loadPackages()
                }
            } catch {
                await MainActor.run {
                    self.actionMessage = "Action failed: \(error.localizedDescription)"
                    self.isActionError = true
                }
            }
        }
    }

    private func backupApk(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(app.displayName).apk"
        panel.allowedContentTypes = [UTType(filenameExtension: "apk")].compactMap { $0 }
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let destinationURL = panel.url {
            Task {
                var path = app.apkPath
                if path.isEmpty {
                    path = (try? await ADBManager.shared.resolvePackageApkPath(serial: device.id, packageName: app.packageName)) ?? ""
                }
                guard !path.isEmpty else {
                    await MainActor.run {
                        self.actionMessage = "Could not locate APK for \(app.displayName)"
                        self.isActionError = true
                    }
                    return
                }

                TransferManager.shared.enqueueDownload(
                    serial: device.id,
                    remotePath: path,
                    filename: "\(app.displayName).apk",
                    sizeBytes: app.sizeBytes,
                    destinationURL: destinationURL,
                    isDirectory: false
                )
                await MainActor.run {
                    self.actionMessage = "Queued \(app.displayName) APK backup"
                    self.isActionError = false
                }
            }
        }
    }

    private func exportSelectedApks() {
        guard let device = appState.selectedDevice else { return }
        let appsToExport = selectedAppsList
        guard !appsToExport.isEmpty else { return }

        if appsToExport.count == 1, let single = appsToExport.first {
            backupApk(single)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export \(appsToExport.count) APKs Here"
        panel.message = "Choose destination directory on Mac for APK backups"

        if panel.runModal() == .OK, let targetDirURL = panel.url {
            actionMessage = "Queuing backup for \(appsToExport.count) APKs..."
            isActionError = false
            Task {
                var exportedCount = 0
                for app in appsToExport {
                    var path = app.apkPath
                    if path.isEmpty {
                        path = (try? await ADBManager.shared.resolvePackageApkPath(serial: device.id, packageName: app.packageName)) ?? ""
                    }
                    if !path.isEmpty {
                        let filename = "\(app.displayName.replacingOccurrences(of: "/", with: "-")).apk"
                        let dest = targetDirURL.appendingPathComponent(filename)
                        TransferManager.shared.enqueueDownload(
                            serial: device.id,
                            remotePath: path,
                            filename: filename,
                            sizeBytes: app.sizeBytes,
                            destinationURL: dest,
                            isDirectory: false
                        )
                        exportedCount += 1
                    }
                }
                let total = exportedCount
                await MainActor.run {
                    self.actionMessage = "Queued \(total) APK backups to \(targetDirURL.lastPathComponent)"
                    self.isActionError = false
                }
            }
        }
    }

    private func promptClearData(_ app: AppInfo) {
        appToClearData = app
        showClearDataAlert = true
    }

    private func executeClearData(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        actionMessage = "Clearing data for \(app.displayName)..."
        isActionError = false
        Task {
            do {
                let res = try await ADBManager.shared.clearAppData(serial: device.id, packageName: app.packageName)
                await MainActor.run {
                    self.actionMessage = "Cleared: \(res.trimmingCharacters(in: .whitespacesAndNewlines))"
                    self.isActionError = false
                }
            } catch {
                await MainActor.run {
                    self.actionMessage = "Failed to clear data: \(error.localizedDescription)"
                    self.isActionError = true
                }
            }
        }
    }

    private func promptUninstall(_ app: AppInfo) {
        appToUninstall = app
        showUninstallAlert = true
    }

    private func executeUninstall(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        actionMessage = "Uninstalling \(app.displayName)..."
        isActionError = false
        Task {
            do {
                _ = try await ADBManager.shared.executeAdb(["-s", device.id, "uninstall", app.packageName])
                await MainActor.run {
                    self.actionMessage = "Uninstalled \(app.displayName) successfully"
                    self.isActionError = false
                    self.appState.loadPackages()
                }
            } catch {
                await MainActor.run {
                    self.actionMessage = "Uninstall failed: \(error.localizedDescription)"
                    self.isActionError = true
                }
            }
        }
    }

    private func inspectApp(_ app: AppInfo) {
        guard let device = appState.selectedDevice else { return }
        inspectingApp = app
        isLoadingDetails = true
        Task {
            let details = await ADBManager.shared.fetchAppDetails(serial: device.id, packageName: app.packageName)
            await MainActor.run {
                self.appDetails = details
                self.isLoadingDetails = false
            }
        }
    }

    // MARK: - APK File Installation

    private func promptInstallApk() {
        guard let device = appState.selectedDevice else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let extensions = ["apk", "xapk", "apks", "apkm", "zip"]
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Install on Phone"
        panel.message = "Choose APK, XAPK, or Split App Bundles to install"

        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                installApkFiles(urls: urls, serial: device.id)
            }
        }
    }

    private func handleApkDrop(providers: [NSItemProvider]) -> Bool {
        guard let device = appState.selectedDevice else { return false }
        final class URLCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var urls: [URL] = []

            func append(_ url: URL) {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }

            var allURLs: [URL] {
                lock.lock()
                defer { lock.unlock() }
                return urls
            }
        }

        let collector = URLCollector()
        let group = DispatchGroup()
        let supportedExtensions: Set<String> = ["apk", "xapk", "apks", "apkm", "zip"]

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    if supportedExtensions.contains(url.pathExtension.lowercased()) {
                        collector.append(url)
                    }
                } else if let url = item as? URL, supportedExtensions.contains(url.pathExtension.lowercased()) {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collector.allURLs
            if !urls.isEmpty {
                self.installApkFiles(urls: urls, serial: device.id)
            }
        }
        return true
    }

    private func installApkFiles(urls: [URL], serial: String) {
        guard !urls.isEmpty else { return }
        isPerformingAction = true
        isActionError = false
        actionMessage = "Installing \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) package(s)")..."

        Task {
            var errors: [String] = []
            var successCount = 0

            for url in urls {
                await MainActor.run {
                    self.actionMessage = "Installing \(url.lastPathComponent)..."
                }
                do {
                    _ = try await ADBManager.shared.installPackageBundle(serial: serial, fileURL: url)
                    successCount += 1
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.isPerformingAction = false
                if errors.isEmpty {
                    self.actionMessage = urls.count == 1 ? "Successfully installed \(urls[0].lastPathComponent)" : "Successfully installed \(successCount) packages"
                    self.isActionError = false
                } else if successCount > 0 {
                    self.actionMessage = "Installed \(successCount) of \(urls.count). Errors: \(errors.joined(separator: "; "))"
                    self.isActionError = true
                } else {
                    self.actionMessage = "Installation failed: \(errors.joined(separator: "; "))"
                    self.isActionError = true
                }
                self.appState.loadPackages()
            }
        }
    }
}

// MARK: - App Row View

private struct AppRowView: View {
    let app: AppInfo
    let isSelected: Bool
    let onLaunch: () -> Void
    let onForceStop: () -> Void
    let onBackupApk: () -> Void
    let onInspect: () -> Void
    let onToggleEnabled: () -> Void
    let onClearDataPrompt: () -> Void
    let onUninstallPrompt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App Icon Graphic
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(app.isSystemApp ? Color.orange.opacity(0.15) : (app.isEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15)))
                    .frame(width: 32, height: 32)
                Image(systemName: app.isSystemApp ? "gearshape.fill" : (app.isEnabled ? "app.badge.fill" : "snowflake"))
                    .foregroundColor(app.isSystemApp ? .orange : (app.isEnabled ? .green : .secondary))
                    .font(.system(size: 15))
            }

            // Name & Package
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if app.isSystemApp {
                        Text("SYSTEM")
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }

                    if !app.isEnabled {
                        Text("FROZEN")
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                }

                Text(app.packageName)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Quick Actions Toolbar
            HStack(spacing: 6) {
                Button(action: onLaunch) {
                    Image(systemName: "play.circle")
                }
                .help("Launch on Phone")
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.accentColor)

                Button(action: onForceStop) {
                    Image(systemName: "stop.circle")
                }
                .help("Force Stop")
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)

                Button(action: onBackupApk) {
                    Image(systemName: "arrow.down.circle")
                }
                .help("Backup APK to Mac")
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)

                Button(action: onInspect) {
                    Image(systemName: "info.circle")
                }
                .help("App Details & Permissions")
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)

                Button(action: onUninstallPrompt) {
                    Image(systemName: "trash")
                }
                .help("Uninstall App")
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.red.opacity(0.8))
            }
            .font(.system(size: 14))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - App Inspector Sheet

private struct AppInspectorSheet: View {
    let app: AppInfo
    let details: AppDetailedInfo?
    let isLoading: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "app.badge.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 22))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(app.packageName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close", action: onClose)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching package metadata...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let d = details {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Specs Grid
                        VStack(spacing: 8) {
                            DetailRow(label: "Version Name", value: d.versionName.isEmpty ? "Unknown" : d.versionName)
                            DetailRow(label: "Version Code", value: d.versionCode.isEmpty ? "Unknown" : d.versionCode)
                            DetailRow(label: "Target SDK", value: d.targetSdk.isEmpty ? "Unknown" : "API \(d.targetSdk)")
                            DetailRow(label: "Min SDK", value: d.minSdk.isEmpty ? "Unknown" : "API \(d.minSdk)")
                            DetailRow(label: "First Installed", value: d.firstInstallTime.isEmpty ? "--" : d.firstInstallTime)
                            DetailRow(label: "Last Updated", value: d.lastUpdateTime.isEmpty ? "--" : d.lastUpdateTime)
                            DetailRow(label: "APK Path", value: d.apkPath.isEmpty ? app.apkPath : d.apkPath)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        // Permissions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Granted Permissions (\(d.permissions.count))")
                                .font(.headline)

                            if d.permissions.isEmpty {
                                Text("No declared dangerous permissions.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(d.permissions, id: \.self) { perm in
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.shield.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 11))
                                            Text(perm)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 520, height: 480)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(2)
            Spacer()
        }
    }
}
