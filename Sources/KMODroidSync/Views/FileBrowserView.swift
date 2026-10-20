import SwiftUI
import UniformTypeIdentifiers

public struct FileBrowserView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var previewManager = PreviewManager.shared
    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""
    @State private var isTargetedForDrop = false

    public var body: some View {
        VStack(spacing: 0) {
            // Path Navigation & Action Bar
            HStack(spacing: 12) {
                // Back / Up Button
                Button(action: goUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(appState.currentPath == "/sdcard" || appState.currentPath == "/")
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

                Spacer()

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search files...", text: $appState.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(width: 140)
                    if !appState.searchText.isEmpty {
                        Button(action: { appState.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

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

                Button(action: downloadSelectedFile) {
                    Image(systemName: "arrow.down.circle")
                }
                .disabled(appState.selectedFile == nil)
                .help("Download to Mac")

                Button(action: deleteSelectedFile) {
                    Image(systemName: "trash")
                }
                .disabled(appState.selectedFile == nil)
                .help("Delete File")

                Button(action: {
                    appState.loadFiles(at: appState.currentPath)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // File Table / List
            if appState.isLoadingFiles {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading files...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.filteredFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("This folder is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Drag files from your Mac here to upload them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.filteredFiles, id: \.id, selection: $appState.selectedFile) { file in
                    FileRowView(file: file, isSelected: appState.selectedFile?.id == file.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if file.isDirectory {
                                appState.navigateTo(path: file.path)
                            } else {
                                triggerQuickLook(file: file)
                            }
                        }
                        .onTapGesture(count: 1) {
                            appState.selectedFile = file
                        }
                        .contextMenu {
                            Button("Quick Look Preview (Space)") {
                                triggerQuickLook(file: file)
                            }
                            Button("Download to Mac...") {
                                downloadFile(file)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteSpecificFile(file)
                            }
                        }
                }
                .listStyle(PlainListStyle())
            }
        }
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
        .sheet(isPresented: $previewManager.isPreviewing) {
            if let url = previewManager.previewURL {
                QuickLookModalView(url: url) {
                    previewManager.closePreview()
                }
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
            items.append(BreadcrumbItem(name: part, path: accumulator))
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
        if !parent.isEmpty && parent != "/" {
            appState.navigateTo(path: parent)
        }
    }

    private func triggerQuickLook(file: DeviceFile) {
        guard let device = appState.selectedDevice else { return }
        Task {
            await previewManager.quickLook(file: file, serial: device.id)
        }
    }

    private func downloadSelectedFile() {
        guard let file = appState.selectedFile else { return }
        downloadFile(file)
    }

    private func downloadFile(_ file: DeviceFile) {
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
            // Reload files after upload finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                appState.loadFiles(at: appState.currentPath)
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

    private func deleteSelectedFile() {
        guard let file = appState.selectedFile else { return }
        deleteSpecificFile(file)
    }

    private func deleteSpecificFile(_ file: DeviceFile) {
        guard let device = appState.selectedDevice else { return }
        Task {
            try? await ADBManager.shared.delete(serial: device.id, remotePath: file.path)
            appState.loadFiles(at: appState.currentPath)
        }
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

private struct FileRowView: View {
    let file: DeviceFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.category.systemImageName)
                .foregroundColor(file.isDirectory ? .blue : .secondary)
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
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
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

private struct QuickLookModalView: View {
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
