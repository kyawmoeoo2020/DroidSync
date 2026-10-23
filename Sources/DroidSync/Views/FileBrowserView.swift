import SwiftUI
import UniformTypeIdentifiers
import AppKit

public enum BrowserLayoutMode: String, CaseIterable, Identifiable {
    case list = "list"
    case grid = "grid"

    public var id: String { rawValue }
}

public struct FileBrowserView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var previewManager = PreviewManager.shared
    @AppStorage("fileBrowserLayoutMode") private var layoutMode: BrowserLayoutMode = .list
    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""
    @State private var isTargetedForDrop = false
    @State private var showingDeleteConfirmation = false
    @State private var browserMessage = ""
    @State private var isBrowserError = false

    // In-place Rename state
    @State private var showingRenameDialog = false
    @State private var fileToRename: DeviceFile?
    @State private var newFileName = ""

    // Deep Device Search state
    @State private var isDeepSearch = false
    @State private var isPerformingDeepSearch = false
    @State private var deepSearchResults: [DeviceFile] = []

    private var displayedFiles: [DeviceFile] {
        if isDeepSearch && !appState.searchText.isEmpty {
            return deepSearchResults
        }
        return appState.filteredFiles
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Path Navigation & Action Bar
            HStack(spacing: 12) {
                // Back / Up Button
                Button(action: goUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(appState.currentPath == "/sdcard" || appState.currentPath == "/" || appState.currentPath == "/storage/emulated/0")
                .help("Go to parent directory")

                // Breadcrumbs Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(pathComponents, id: \.self) { component in
                            Button(action: {
                                navigateToBreadcrumb(component)
                            }) {
                                Text(component.name)
                                    .font(.subheadline)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if component.path != appState.currentPath {
                                Text("/")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 26)

                Spacer()

                // Selection Pill Badge (when items are selected)
                if !appState.selectedFileIDs.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)

                        Text("\(appState.selectedFileIDs.count) selected (\(appState.formattedSelectedSize))")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Button(action: {
                            appState.selectedFileIDs.removeAll()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Deselect all")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(12)
                }

                // Search Bar with Scope Menu
                HStack(spacing: 5) {
                    Menu {
                        Button {
                            isDeepSearch = false
                            deepSearchResults.removeAll()
                        } label: {
                            Label("Current Folder Only", systemImage: "folder")
                        }

                        Button {
                            isDeepSearch = true
                            performDeepSearch()
                        } label: {
                            Label("Everywhere on Device (Deep Search)", systemImage: "globe")
                        }
                    } label: {
                        Image(systemName: isDeepSearch ? "globe" : "folder")
                            .foregroundColor(isDeepSearch ? .accentColor : .secondary)
                            .font(.system(size: 11))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .frame(width: 18)
                    .help(isDeepSearch ? "Deep Search everywhere on Android storage" : "Searching current folder")

                    TextField(isDeepSearch ? "Deep search device..." : "Search files...", text: $appState.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(width: 135)
                        .onSubmit {
                            if isDeepSearch {
                                performDeepSearch()
                            }
                        }

                    if isPerformingDeepSearch {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    } else if !appState.searchText.isEmpty {
                        Button(action: {
                            appState.searchText = ""
                            deepSearchResults.removeAll()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                // Layout Mode Picker (List vs Grid)
                Picker("Layout Mode", selection: $layoutMode) {
                    Image(systemName: "list.bullet")
                        .tag(BrowserLayoutMode.list)
                    Image(systemName: "square.grid.2x2")
                        .tag(BrowserLayoutMode.grid)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 66)
                .help(layoutMode == .list ? "Switch to Grid View" : "Switch to List View")

                // Select All / Deselect All Toggle
                Button(action: appState.toggleSelectAll) {
                    Image(systemName: appState.isAllSelected ? "checkmark.square.fill" : "square")
                }
                .help(appState.isAllSelected ? "Deselect All (⌘A)" : "Select All (⌘A)")
                .disabled(appState.filteredFiles.isEmpty)

                // Action Buttons
                Button(action: {
                    showingNewFolderDialog = true
                }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Button(action: promptUploadFiles) {
                    Image(systemName: "arrow.up.circle")
                }
                .help("Upload to Phone")

                // Download Button (supports single & batch)
                Button(action: downloadSelectedFiles) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        if appState.selectedFileIDs.count > 1 {
                            Text("\(appState.selectedFileIDs.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                    }
                }
                .disabled(appState.selectedFileIDs.isEmpty)
                .help(appState.selectedFileIDs.count > 1 ? "Download \(appState.selectedFileIDs.count) Selected Items to Mac" : "Download Selected Item to Mac")

                // Delete Button (supports single & batch)
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .foregroundColor(appState.selectedFileIDs.isEmpty ? .secondary : .red)
                        if appState.selectedFileIDs.count > 1 {
                            Text("\(appState.selectedFileIDs.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                }
                .disabled(appState.selectedFileIDs.isEmpty)
                .help(appState.selectedFileIDs.count > 1 ? "Delete \(appState.selectedFileIDs.count) Selected Items" : "Delete Selected Item")

                Button(action: {
                    appState.loadFiles(at: appState.currentPath)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(height: 44)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Status / Action Banner
            if !browserMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: isBrowserError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(isBrowserError ? .red : .green)
                    Text(browserMessage)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Dismiss") {
                        browserMessage = ""
                    }
                    .font(.caption)
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isBrowserError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))

                Divider()
            }

            // Deep Search Active Banner
            if isDeepSearch && !appState.searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(.accentColor)
                    Text("Deep Search: Found \(deepSearchResults.count) item\(deepSearchResults.count == 1 ? "" : "s") across device for \"\(appState.searchText)\"")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Exit Deep Search") {
                        isDeepSearch = false
                        deepSearchResults.removeAll()
                        appState.searchText = ""
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))

                Divider()
            }

            // File Table / List / Grid
            if appState.isLoadingFiles {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading files...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: isDeepSearch ? "magnifyingglass" : "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(isDeepSearch ? "No files found" : "This folder is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(isDeepSearch ? "Try searching for a different keyword or file extension." : "Drag files from your Mac here to upload them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layoutMode == .list {
                renderListView()
            } else {
                renderGridView()
            }
        }
        // Keyboard shortcuts
        .onDeleteCommand {
            if !appState.selectedFileIDs.isEmpty {
                showingDeleteConfirmation = true
            }
        }
        .background(
            Group {
                Button("") {
                    appState.toggleSelectAll()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("") {
                    if let firstId = appState.selectedFileIDs.first,
                       let file = appState.filteredFiles.first(where: { $0.id == firstId }) {
                        triggerQuickLook(file: file)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            .opacity(0)
        )
        // Drag and drop from macOS Finder
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            isTargetedForDrop ?
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                : nil
        )
        .sheet(isPresented: $showingNewFolderDialog) {
            NewFolderSheet(folderName: $newFolderName) {
                createFolder()
            }
        }
        .sheet(isPresented: $showingRenameDialog) {
            RenameItemSheet(
                originalName: fileToRename?.name ?? "",
                newName: $newFileName,
                onConfirm: executeRename,
                onCancel: {
                    showingRenameDialog = false
                    fileToRename = nil
                }
            )
        }
        .sheet(isPresented: $previewManager.isPreviewing) {
            if let url = previewManager.previewURL {
                QuickLookModalView(url: url) {
                    previewManager.closePreview()
                }
            }
        }
        // Multi-Item Delete Confirmation Alert
        .alert(
            "Delete \(appState.selectedFileIDs.count) item\(appState.selectedFileIDs.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                executeDeleteSelectedFiles()
            }
        } message: {
            Text("Are you sure you want to permanently delete \(appState.selectedFileIDs.count) selected item\(appState.selectedFileIDs.count == 1 ? "" : "s") (\(appState.formattedSelectedSize)) from Internal Storage? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func renderListView() -> some View {
        List {
            ForEach(displayedFiles) { file in
                let isSelected = appState.selectedFileIDs.contains(file.id)

                FileRowView(
                    file: file,
                    isSelected: isSelected,
                    onToggleSelection: {
                        appState.toggleSelection(for: file)
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleClick(file: file)
                }
                .onTapGesture(count: 1) {
                    handleSingleClick(file: file)
                }
                .contextMenu {
                    fileContextMenu(for: file)
                }
            }
        }
        .listStyle(PlainListStyle())
    }

    @ViewBuilder
    private func renderGridView() -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 105, maximum: 135), spacing: 14)
                ],
                spacing: 14
            ) {
                ForEach(displayedFiles) { file in
                    let isSelected = appState.selectedFileIDs.contains(file.id)

                    FileGridItemView(
                        file: file,
                        isSelected: isSelected,
                        onToggleSelection: {
                            appState.toggleSelection(for: file)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        handleDoubleClick(file: file)
                    }
                    .onTapGesture(count: 1) {
                        handleSingleClick(file: file)
                    }
                    .contextMenu {
                        fileContextMenu(for: file)
                    }
                }
            }
            .padding(16)
        }
    }

    private func handleDoubleClick(file: DeviceFile) {
        if file.isDirectory {
            if isDeepSearch {
                isDeepSearch = false
                deepSearchResults.removeAll()
                appState.searchText = ""
            }
            appState.navigateTo(path: file.path)
        } else {
            triggerQuickLook(file: file)
        }
    }

    private func handleSingleClick(file: DeviceFile) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            appState.toggleSelection(for: file)
        } else if flags.contains(.shift) {
            appState.selectRange(to: file)
        } else {
            let isSelected = appState.selectedFileIDs.contains(file.id)
            if isSelected && appState.selectedFileIDs.count == 1 {
                appState.selectedFileIDs.removeAll()
                appState.lastSelectedFileID = nil
            } else {
                appState.selectSingleFile(file)
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(for file: DeviceFile) -> some View {
        if appState.selectedFileIDs.contains(file.id) && appState.selectedFileIDs.count > 1 {
            Button("Download \(appState.selectedFileIDs.count) Selected Items to Mac...") {
                downloadSelectedFiles()
            }
            Divider()
            Button("Delete \(appState.selectedFileIDs.count) Selected Items", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } else {
            if file.category == .apk {
                Button("Install APK on Phone") {
                    installRemoteApk(file: file)
                }
                Divider()
            }
            Button("Quick Look Preview (Space)") {
                triggerQuickLook(file: file)
            }
            Button("Download to Mac...") {
                appState.selectSingleFile(file)
                downloadSelectedFiles()
            }
            Button("Rename...") {
                promptRename(file)
            }
            Divider()
            Button("Delete", role: .destructive) {
                appState.selectSingleFile(file)
                showingDeleteConfirmation = true
            }
        }
    }

    private struct BreadcrumbItem: Hashable {
        let name: String
        let path: String
    }

    private var pathComponents: [BreadcrumbItem] {
        let path = appState.currentPath
        let parts = path.split(separator: "/").map(String.init)
        var items: [BreadcrumbItem] = []
        var accumulator = ""

        for part in parts {
            accumulator += "/" + part
            let displayName = (part == "sdcard" || part == "0") ? "Internal Storage" : part
            items.append(BreadcrumbItem(name: displayName, path: accumulator))
        }

        if items.isEmpty {
            items.append(BreadcrumbItem(name: "Internal Storage", path: "/sdcard"))
        }

        return items
    }

    private func navigateToBreadcrumb(_ item: BreadcrumbItem) {
        appState.navigateTo(path: item.path)
    }

    private func goUp() {
        let current = appState.currentPath as NSString
        let parent = current.deletingLastPathComponent
        let roots = ["/sdcard", "/storage/emulated/0", "/storage/self/primary", "/", "/storage/emulated", "/storage"]
        if !roots.contains(appState.currentPath) && !roots.contains(parent) && !parent.isEmpty {
            appState.navigateTo(path: parent)
        } else {
            appState.navigateTo(path: "/sdcard")
        }
    }

    private func triggerQuickLook(file: DeviceFile) {
        guard let device = appState.selectedDevice else { return }
        Task {
            await previewManager.quickLook(file: file, serial: device.id)
        }
    }

    private func downloadSelectedFiles() {
        guard let device = appState.selectedDevice else { return }
        let selected = appState.selectedFiles
        guard !selected.isEmpty else { return }

        if selected.count == 1, let file = selected.first {
            if file.isDirectory {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Download Folder Here"
                panel.message = "Choose destination folder on your Mac"

                if panel.runModal() == .OK, let targetDirURL = panel.url {
                    let dest = targetDirURL.appendingPathComponent(file.name)
                    TransferManager.shared.enqueueDownload(
                        serial: device.id,
                        remotePath: file.path,
                        filename: file.name,
                        sizeBytes: file.sizeBytes,
                        destinationURL: dest,
                        isDirectory: true
                    )
                }
            } else {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = file.name
                panel.canCreateDirectories = true

                if panel.runModal() == .OK, let destinationURL = panel.url {
                    TransferManager.shared.enqueueDownload(
                        serial: device.id,
                        remotePath: file.path,
                        filename: file.name,
                        sizeBytes: file.sizeBytes,
                        destinationURL: destinationURL,
                        isDirectory: false
                    )
                }
            }
        } else {
            // Multiple items: select destination folder
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Download \(selected.count) Items Here"
            panel.message = "Choose destination folder on your Mac"

            if panel.runModal() == .OK, let targetDirURL = panel.url {
                for file in selected {
                    let dest = targetDirURL.appendingPathComponent(file.name)
                    TransferManager.shared.enqueueDownload(
                        serial: device.id,
                        remotePath: file.path,
                        filename: file.name,
                        sizeBytes: file.sizeBytes,
                        destinationURL: dest,
                        isDirectory: file.isDirectory
                    )
                }
            }
        }
    }

    private func executeDeleteSelectedFiles() {
        guard let device = appState.selectedDevice else { return }
        let pathsToDelete = Array(appState.selectedFileIDs)
        guard !pathsToDelete.isEmpty else { return }

        Task {
            do {
                try await ADBManager.shared.deleteMultiple(serial: device.id, remotePaths: pathsToDelete)
                await MainActor.run {
                    appState.selectedFileIDs.removeAll()
                    appState.lastSelectedFileID = nil
                    appState.loadFiles(at: appState.currentPath)
                    browserMessage = "Deleted \(pathsToDelete.count) item\(pathsToDelete.count == 1 ? "" : "s") successfully"
                    isBrowserError = false
                }
            } catch {
                await MainActor.run {
                    browserMessage = "Failed to delete: \(error.localizedDescription)"
                    isBrowserError = true
                }
            }
        }
    }

    private func promptRename(_ file: DeviceFile) {
        fileToRename = file
        newFileName = file.name
        showingRenameDialog = true
    }

    private func executeRename() {
        guard let device = appState.selectedDevice, let file = fileToRename else { return }
        let targetName = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetName.isEmpty, targetName != file.name else {
            showingRenameDialog = false
            return
        }

        showingRenameDialog = false
        Task {
            do {
                try await ADBManager.shared.renamePath(serial: device.id, oldPath: file.path, newName: targetName)
                await MainActor.run {
                    self.browserMessage = "Renamed to \"\(targetName)\""
                    self.isBrowserError = false
                    self.appState.loadFiles(at: self.appState.currentPath)
                }
            } catch {
                await MainActor.run {
                    self.browserMessage = "Rename failed: \(error.localizedDescription)"
                    self.isBrowserError = true
                }
            }
        }
    }

    private func performDeepSearch() {
        guard let device = appState.selectedDevice else { return }
        let query = appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            deepSearchResults.removeAll()
            return
        }

        isPerformingDeepSearch = true
        browserMessage = "Searching device storage..."
        isBrowserError = false

        Task {
            do {
                let results = try await ADBManager.shared.searchFiles(serial: device.id, basePath: "/sdcard", query: query)
                await MainActor.run {
                    self.deepSearchResults = results
                    self.isPerformingDeepSearch = false
                    self.isDeepSearch = true
                    if results.isEmpty {
                        self.browserMessage = "No files found matching \"\(query)\""
                    } else {
                        self.browserMessage = "Found \(results.count) item\(results.count == 1 ? "" : "s") across storage"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPerformingDeepSearch = false
                    self.browserMessage = "Deep search error: \(error.localizedDescription)"
                    self.isBrowserError = true
                }
            }
        }
    }

    private func installRemoteApk(file: DeviceFile) {
        guard let device = appState.selectedDevice else { return }
        browserMessage = "Installing \(file.name) on device..."
        isBrowserError = false

        Task {
            do {
                _ = try await ADBManager.shared.installApkOnDevice(serial: device.id, remotePath: file.path)
                await MainActor.run {
                    browserMessage = "Successfully installed \(file.name) on device"
                    isBrowserError = false
                }
            } catch {
                await MainActor.run {
                    browserMessage = "Installation failed: \(error.localizedDescription)"
                    isBrowserError = true
                }
            }
        }
    }

    private func promptUploadFiles() {
        guard let device = appState.selectedDevice else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                TransferManager.shared.enqueueUpload(
                    serial: device.id,
                    localURL: url,
                    remoteDirectory: appState.currentPath
                )
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let device = appState.selectedDevice else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        TransferManager.shared.enqueueUpload(
                            serial: device.id,
                            localURL: url,
                            remoteDirectory: appState.currentPath
                        )
                    }
                } else if let url = item as? URL {
                    DispatchQueue.main.async {
                        TransferManager.shared.enqueueUpload(
                            serial: device.id,
                            localURL: url,
                            remoteDirectory: appState.currentPath
                        )
                    }
                }
            }
        }
        return true
    }

    private func createFolder() {
        guard !newFolderName.isEmpty, let device = appState.selectedDevice else { return }
        let path = "\(appState.currentPath)/\(newFolderName)"
        Task {
            try? await ADBManager.shared.createDirectory(serial: device.id, remotePath: path)
            newFolderName = ""
            showingNewFolderDialog = false
            appState.loadFiles(at: appState.currentPath)
        }
    }
}

private func categoryColor(for file: DeviceFile) -> Color {
    switch file.category {
    case .folder: return .blue
    case .image: return .purple
    case .video: return .orange
    case .audio: return .pink
    case .document: return .teal
    case .apk: return .green
    case .archive: return .indigo
    case .other: return .secondary
    }
}

private struct FileRowView: View {
    let file: DeviceFile
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox selection toggle
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.35))
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())

            Image(systemName: file.category.systemImageName)
                .foregroundColor(categoryColor(for: file))
                .frame(width: 20)

            Text(file.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(file.permissions)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }
}

private struct FileGridItemView: View {
    let file: DeviceFile
    let isSelected: Bool
    let onToggleSelection: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Card thumbnail / icon container
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06)))
                    .frame(width: 86, height: 86)
                    .overlay(
                        Image(systemName: file.category.systemImageName)
                            .font(.system(size: 38))
                            .foregroundColor(categoryColor(for: file))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                // Selection checkmark toggle in corner
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                        .font(.system(size: 16))
                        .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(4)
                .opacity(isSelected || isHovered ? 1.0 : 0.0)
            }

            VStack(spacing: 2) {
                Text(file.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)

                Text(file.isDirectory ? "Folder" : file.formattedSize)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(width: 96)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct NewFolderSheet: View {
    @Binding var folderName: String
    @Environment(\.dismiss) var dismiss
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Folder")
                .font(.headline)

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 250)

            HStack {
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

struct QuickLookModalView: View {
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

            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 600, maxHeight: 500)
                    .padding()
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 600, height: 400)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Preview not available directly in app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Open in Default Mac App") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .frame(width: 450, height: 300)
            }
        }
    }
}

// MARK: - Rename Item Sheet

private struct RenameItemSheet: View {
    let originalName: String
    @Binding var newName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Item")
                .font(.headline)

            Text("Enter a new name for \"\(originalName)\":")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("New name", text: $newName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 320)
                .onSubmit {
                    if !newName.trimmingCharacters(in: .whitespaces).isEmpty && newName != originalName {
                        onConfirm()
                    }
                }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Rename", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newName == originalName)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
