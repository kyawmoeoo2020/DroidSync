import SwiftUI
import AppKit

public struct StorageLensView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var previewManager = PreviewManager.shared

    public enum LensTab: String, CaseIterable, Identifiable {
        case folders = "Folder Breakdown"
        case largeFiles = "Large Space Wasters"
        public var id: String { rawValue }
    }

    @State private var currentTab: LensTab = .folders
    @State private var currentFolderPath: String = "/sdcard"
    @State private var folderItems: [StorageFolderItem] = []
    @State private var largeFileItems: [StorageLargeFile] = []
    @State private var isScanning = false
    @State private var minSizeThresholdMB: Int = 25
    @State private var actionFeedback: String = ""

    // Deletion Confirmation
    @State private var folderToDelete: StorageFolderItem?
    @State private var showDeleteFolderAlert = false
    @State private var fileToDelete: StorageLargeFile?
    @State private var showDeleteFileAlert = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header Card
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storage Lens")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Analyze disk space, drill down into heavy folders, and delete gigabyte-hogging files.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Mode Switcher
                    Picker("", selection: $currentTab) {
                        ForEach(LensTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 300)

                    // Rescan Button
                    Button(action: rescanCurrentView) {
                        Label(isScanning ? "Scanning..." : "Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(isScanning)
                }

                // Device Storage Summary Bar
                if let device = appState.selectedDevice {
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(height: 10)

                                RoundedRectangle(cornerRadius: 5)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple, Color.accentColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(device.storage.usedPercentage), height: 10)
                            }
                        }
                        .frame(height: 10)

                        HStack {
                            Text("Used: \(device.storage.formattedUsed) (\(String(format: "%.1f%%", device.storage.usedPercentage * 100)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Free: \(device.storage.formattedFree) available of \(device.storage.formattedTotal)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Sub-Toolbar / Breadcrumbs or Filter
            HStack(spacing: 10) {
                if currentTab == .folders {
                    // Navigation Breadcrumbs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button(action: {
                                navigateToFolder("/sdcard")
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "internaldrive.fill")
                                        .font(.system(size: 11))
                                    Text("Internal Storage")
                                }
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())

                            ForEach(folderBreadcrumbs, id: \.path) { crumb in
                                Text("/")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Button(action: {
                                    navigateToFolder(crumb.path)
                                }) {
                                    Text(crumb.name)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(height: 26)

                    Spacer()

                    if !isAtRootFolder {
                        Button(action: goUpFolder) {
                            Label("Up", systemImage: "arrow.up")
                                .font(.caption)
                        }
                    }

                } else {
                    // Large Files Threshold Filter
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $minSizeThresholdMB) {
                        Text("> 25 MB").tag(25)
                        Text("> 50 MB").tag(50)
                        Text("> 100 MB").tag(100)
                        Text("> 500 MB").tag(500)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 320)
                    .onChange(of: minSizeThresholdMB) { _, _ in
                        scanLargeFiles()
                    }

                    Spacer()

                    Text("\(largeFileItems.count) large files found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(height: 38)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Status message
            if !actionFeedback.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(actionFeedback)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { actionFeedback = "" }
                        .font(.caption2)
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
                Divider()
            }

            // Main Content Area
            if isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(currentTab == .folders ? "Calculating directory sizes for \(currentFolderPath)..." : "Scanning phone for files > \(minSizeThresholdMB)MB...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentTab == .folders {
                renderFolderBreakdown()
            } else {
                renderLargeFilesList()
            }
        }
        // Folder Delete Confirmation
        .alert("Delete Folder \(folderToDelete?.name ?? "")?", isPresented: $showDeleteFolderAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Folder", role: .destructive) {
                if let item = folderToDelete {
                    executeDeleteFolder(item)
                }
            }
        } message: {
            if let item = folderToDelete {
                Text("This will permanently delete '\(item.path)' and all of its contents (\(item.formattedSize)) from the device.")
            }
        }
        // File Delete Confirmation
        .alert("Delete File \(fileToDelete?.name ?? "")?", isPresented: $showDeleteFileAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete File", role: .destructive) {
                if let file = fileToDelete {
                    executeDeleteLargeFile(file)
                }
            }
        } message: {
            if let file = fileToDelete {
                Text("This will permanently remove '\(file.name)' (\(file.formattedSize)) from '\(file.path)'.")
            }
        }
        .sheet(isPresented: $previewManager.isPreviewing) {
            if let url = previewManager.previewURL {
                StorageQuickLookModal(url: url) {
                    previewManager.closePreview()
                }
            }
        }
        .onAppear {
            if folderItems.isEmpty {
                scanFolderBreakdown()
            }
        }
        .onChange(of: currentTab) { _, newTab in
            if newTab == .largeFiles && largeFileItems.isEmpty {
                scanLargeFiles()
            } else if newTab == .folders && folderItems.isEmpty {
                scanFolderBreakdown()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func renderFolderBreakdown() -> some View {
        if folderItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No folders found in this directory")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Button("Scan Internal Storage", action: { navigateToFolder("/sdcard") })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(folderItems) { item in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 15))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.body)
                                .fontWeight(.semibold)

                            Text("• \(String(format: "%.1f%%", item.percentageOfParent * 100))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // Percentage Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: max(3, geo.size.width * CGFloat(item.percentageOfParent)), height: 5)
                            }
                        }
                        .frame(height: 5)
                    }

                    Spacer()

                    Text(item.formattedSize)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 100, alignment: .trailing)

                    // Actions
                    HStack(spacing: 8) {
                        Button(action: {
                            navigateToFolder(item.path)
                        }) {
                            Text("Inspect")
                                .font(.caption)
                        }
                        .help("Inspect subfolders inside this directory")

                        Button(action: {
                            appState.navigateTo(path: item.path)
                        }) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                        .help("Open in File Explorer")

                        Button(action: {
                            folderToDelete = item
                            showDeleteFolderAlert = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Delete Folder")
                    }
                }
                .padding(.vertical, 6)
            }
            .listStyle(PlainListStyle())
        }
    }

    @ViewBuilder
    private func renderLargeFilesList() -> some View {
        if largeFileItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("No files larger than \(minSizeThresholdMB) MB")
                    .font(.headline)
                Text("Try selecting a lower threshold above or scan another folder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(largeFileItems) { file in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: file.category.systemImageName)
                            .foregroundColor(.purple)
                            .font(.system(size: 15))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(file.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(file.formattedSize)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .frame(width: 100, alignment: .trailing)

                    // Quick Actions
                    HStack(spacing: 8) {
                        Button(action: {
                            previewLargeFile(file)
                        }) {
                            Image(systemName: "eye")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                        .help("Quick Look Preview")

                        Button(action: {
                            downloadLargeFile(file)
                        }) {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                        .help("Download to Mac")

                        Button(action: {
                            fileToDelete = file
                            showDeleteFileAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Delete File from Phone")
                    }
                    .font(.system(size: 14))
                }
                .padding(.vertical, 6)
            }
            .listStyle(PlainListStyle())
        }
    }

    private struct LensBreadcrumb: Hashable {
        let name: String
        let path: String
    }

    private var isAtRootFolder: Bool {
        let roots = ["/sdcard", "/storage/emulated/0", "/storage/self/primary", "/"]
        return roots.contains(currentFolderPath)
    }

    private var folderBreadcrumbs: [LensBreadcrumb] {
        var subpath = currentFolderPath
        var base = "/sdcard"
        let knownBases = ["/storage/emulated/0", "/storage/self/primary", "/sdcard"]
        for b in knownBases {
            if subpath.hasPrefix(b) {
                base = b
                subpath = String(subpath.dropFirst(b.count))
                break
            }
        }
        let parts = subpath.split(separator: "/").map(String.init)
        var list: [LensBreadcrumb] = []
        var running = base
        for part in parts {
            running += "/" + part
            list.append(LensBreadcrumb(name: part, path: running))
        }
        return list
    }

    // MARK: - Actions

    private func rescanCurrentView() {
        if currentTab == .folders {
            scanFolderBreakdown()
        } else {
            scanLargeFiles()
        }
    }

    private func navigateToFolder(_ path: String) {
        currentFolderPath = path
        scanFolderBreakdown()
    }

    private func goUpFolder() {
        let parent = (currentFolderPath as NSString).deletingLastPathComponent
        let roots = ["/sdcard", "/storage/emulated/0", "/storage/self/primary", "/", "/storage/emulated", "/storage"]
        if !roots.contains(currentFolderPath) && !roots.contains(parent) && !parent.isEmpty {
            navigateToFolder(parent)
        } else {
            navigateToFolder("/sdcard")
        }
    }

    private func scanFolderBreakdown() {
        guard let device = appState.selectedDevice else { return }
        isScanning = true

        Task {
            do {
                let items = try await ADBManager.shared.scanDirectoryBreakdown(serial: device.id, path: currentFolderPath)
                await MainActor.run {
                    self.folderItems = items
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.actionFeedback = "Failed to scan folder: \(error.localizedDescription)"
                    self.isScanning = false
                }
            }
        }
    }

    private func scanLargeFiles() {
        guard let device = appState.selectedDevice else { return }
        isScanning = true

        Task {
            do {
                let files = try await ADBManager.shared.scanLargeFiles(serial: device.id, path: "/sdcard", minMB: minSizeThresholdMB)
                await MainActor.run {
                    self.largeFileItems = files
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.actionFeedback = "Failed to scan large files: \(error.localizedDescription)"
                    self.isScanning = false
                }
            }
        }
    }

    private func previewLargeFile(_ file: StorageLargeFile) {
        guard let device = appState.selectedDevice else { return }
        let devFile = DeviceFile(
            name: file.name,
            path: file.path,
            isDirectory: false,
            sizeBytes: file.sizeBytes
        )
        Task {
            await previewManager.quickLook(file: devFile, serial: device.id)
        }
    }

    private func downloadLargeFile(_ file: StorageLargeFile) {
        guard let device = appState.selectedDevice else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let destinationURL = panel.url {
            TransferManager.shared.enqueueDownload(
                serial: device.id,
                remotePath: file.path,
                filename: file.name,
                sizeBytes: file.sizeBytes,
                destinationURL: destinationURL
            )
            actionFeedback = "Queued download for \(file.name)"
        }
    }

    private func executeDeleteFolder(_ item: StorageFolderItem) {
        guard let device = appState.selectedDevice else { return }
        Task {
            do {
                try await ADBManager.shared.delete(serial: device.id, remotePath: item.path)
                await MainActor.run {
                    self.actionFeedback = "Deleted folder '\(item.name)'"
                    self.scanFolderBreakdown()
                    self.appState.refreshDevices()
                }
            } catch {
                await MainActor.run {
                    self.actionFeedback = "Failed to delete: \(error.localizedDescription)"
                }
            }
        }
    }

    private func executeDeleteLargeFile(_ file: StorageLargeFile) {
        guard let device = appState.selectedDevice else { return }
        Task {
            do {
                try await ADBManager.shared.delete(serial: device.id, remotePath: file.path)
                await MainActor.run {
                    self.actionFeedback = "Deleted '\(file.name)'"
                    self.scanLargeFiles()
                    self.appState.refreshDevices()
                }
            } catch {
                await MainActor.run {
                    self.actionFeedback = "Failed to delete: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct StorageQuickLookModal: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Close", action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()

            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 600, maxHeight: 500)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Preview ready")
                        .font(.headline)
                    Button("Open in Default Mac App") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .frame(width: 450, height: 280)
            }
        }
    }
}
