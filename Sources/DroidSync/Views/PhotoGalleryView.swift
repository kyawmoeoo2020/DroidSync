import SwiftUI
import AppKit
import ImageIO

public final class MediaThumbnailCache: @unchecked Sendable {
    public static let shared = MediaThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 64 * 1024 * 1024 // 64 MB
    }

    public func thumbnail(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    public func setThumbnail(_ image: NSImage, for path: String) {
        cache.setObject(image, forKey: path as NSString)
    }
}

private func createThumbnail(from data: Data, maxPixelSize: CGFloat = 280) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return NSImage(data: data)
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return NSImage(data: data)
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

public struct PhotoGalleryView: View {
    @ObservedObject var appState: AppState

    @State private var selectedSource: MediaSource = .all
    @State private var mediaItems: [PhotoItem] = []
    @State private var isLoading = false
    @State private var selectedMediaPaths: Set<String> = []
    @State private var minThumbnailWidth: Double = 130.0
    @State private var galleryMessage = ""
    @State private var isGalleryError = false
    @State private var showingDeleteConfirmation = false

    @StateObject private var previewManager = PreviewManager.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Camera & Photos")
                                .font(.title2)
                                .fontWeight(.bold)

                            if !mediaItems.isEmpty {
                                Text("\(mediaItems.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("Explore, preview, and export photos and videos from your Android phone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Selection Chip (when items selected)
                    if !selectedMediaPaths.isEmpty {
                        HStack(spacing: 8) {
                            Text("\(selectedMediaPaths.count) selected")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Button(action: importSelectedMedia) {
                                Label("Import (\(selectedMediaPaths.count))...", systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Delete selected photos")

                            Button(action: { selectedMediaPaths.removeAll() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Deselect all")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Thumbnail Size Slider
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Slider(value: $minThumbnailWidth, in: 95...220)
                            .frame(width: 80)
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .help("Adjust thumbnail size")

                    // Select All / Deselect All
                    Button(action: toggleSelectAll) {
                        Image(systemName: isAllSelected ? "checkmark.square.fill" : "square")
                    }
                    .help(isAllSelected ? "Deselect All (⌘A)" : "Select All (⌘A)")
                    .disabled(mediaItems.isEmpty)

                    // Refresh Button
                    Button(action: loadMedia) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Photos")
                    .disabled(isLoading)
                }

                // Filter Tabs Bar
                HStack(spacing: 8) {
                    ForEach(MediaSource.allCases) { source in
                        Button(action: {
                            selectedSource = source
                            loadMedia()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: source.systemImage)
                                    .font(.system(size: 11))
                                Text(source.rawValue)
                                    .font(.system(size: 12, weight: selectedSource == source ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedSource == source ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundColor(selectedSource == source ? .accentColor : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Status Banner
            if !galleryMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: isGalleryError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(isGalleryError ? .red : .green)
                    Text(galleryMessage)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Dismiss") { galleryMessage = "" }
                        .font(.caption)
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isGalleryError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))

                Divider()
            }

            // Main Content Area
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning photos on device...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mediaItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No media found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("No photos or videos found in \(selectedSource.rawValue).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: CGFloat(minThumbnailWidth), maximum: CGFloat(minThumbnailWidth * 1.35)), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(mediaItems) { item in
                            let isSelected = selectedMediaPaths.contains(item.path)

                            PhotoThumbnailCard(
                                item: item,
                                isSelected: isSelected,
                                serial: appState.selectedDevice?.id ?? ""
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                triggerQuickLook(item: item)
                            }
                            .onTapGesture(count: 1) {
                                handleTap(item: item)
                            }
                            .contextMenu {
                                Button("Quick Look Preview (Space)") {
                                    triggerQuickLook(item: item)
                                }
                                Button("Import to Mac...") {
                                    importSingleMedia(item)
                                }
                                Divider()
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.path, forType: .string)
                                }
                                Divider()
                                Button("Delete Photo...", role: .destructive) {
                                    selectedMediaPaths = [item.path]
                                    showingDeleteConfirmation = true
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            if mediaItems.isEmpty {
                loadMedia()
            }
        }
        .onChange(of: appState.selectedDevice?.id) { _, _ in
            loadMedia()
        }
        // Keyboard Shortcuts
        .background(
            Group {
                Button("") { toggleSelectAll() }
                    .keyboardShortcut("a", modifiers: .command)

                Button("") {
                    if let firstSelected = selectedMediaPaths.first,
                       let item = mediaItems.first(where: { $0.path == firstSelected }) {
                        triggerQuickLook(item: item)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            .opacity(0)
        )
        // QuickLook Sheet
        .sheet(isPresented: $previewManager.isPreviewing) {
            if let url = previewManager.previewURL {
                QuickLookModalView(url: url) {
                    previewManager.closePreview()
                }
            }
        }
        // Delete Confirmation Alert
        .alert(
            "Delete \(selectedMediaPaths.count) photo\(selectedMediaPaths.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                executeDeleteSelectedMedia()
            }
        } message: {
            Text("Are you sure you want to permanently delete \(selectedMediaPaths.count) item\(selectedMediaPaths.count == 1 ? "" : "s") from your Android phone? This action cannot be undone.")
        }
    }

    // MARK: - Actions

    private var isAllSelected: Bool {
        !mediaItems.isEmpty && mediaItems.allSatisfy { selectedMediaPaths.contains($0.path) }
    }

    private func toggleSelectAll() {
        if isAllSelected {
            selectedMediaPaths.removeAll()
        } else {
            selectedMediaPaths = Set(mediaItems.map(\.path))
        }
    }

    private func handleTap(item: PhotoItem) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedMediaPaths.contains(item.path) {
                selectedMediaPaths.remove(item.path)
            } else {
                selectedMediaPaths.insert(item.path)
            }
        } else if NSEvent.modifierFlags.contains(.shift), let last = selectedMediaPaths.first,
                  let lastIdx = mediaItems.firstIndex(where: { $0.path == last }),
                  let curIdx = mediaItems.firstIndex(where: { $0.path == item.path }) {
            let start = min(lastIdx, curIdx)
            let end = max(lastIdx, curIdx)
            for i in start...end {
                selectedMediaPaths.insert(mediaItems[i].path)
            }
        } else {
            if selectedMediaPaths.contains(item.path) && selectedMediaPaths.count == 1 {
                selectedMediaPaths.removeAll()
            } else {
                selectedMediaPaths = [item.path]
            }
        }
    }

    private func loadMedia() {
        guard let device = appState.selectedDevice else { return }
        isLoading = true
        galleryMessage = ""
        isGalleryError = false

        Task {
            do {
                let items = try await ADBManager.shared.fetchMediaFiles(serial: device.id, source: selectedSource)
                await MainActor.run {
                    self.mediaItems = items
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.galleryMessage = "Failed to load photos: \(error.localizedDescription)"
                    self.isGalleryError = true
                }
            }
        }
    }

    private func triggerQuickLook(item: PhotoItem) {
        guard let device = appState.selectedDevice else { return }
        Task {
            await previewManager.quickLook(remotePath: item.path, filename: item.name, serial: device.id)
        }
    }

    private func importSingleMedia(_ item: PhotoItem) {
        guard let device = appState.selectedDevice else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let dest = panel.url {
            TransferManager.shared.enqueueDownload(
                serial: device.id,
                remotePath: item.path,
                filename: item.name,
                sizeBytes: item.sizeBytes,
                destinationURL: dest,
                isDirectory: false
            )
            galleryMessage = "Queued import for \(item.name)"
            isGalleryError = false
        }
    }

    private func importSelectedMedia() {
        guard let device = appState.selectedDevice else { return }
        let selectedItems = mediaItems.filter { selectedMediaPaths.contains($0.path) }
        guard !selectedItems.isEmpty else { return }

        if selectedItems.count == 1, let single = selectedItems.first {
            importSingleMedia(single)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import \(selectedItems.count) Photos Here"
        panel.message = "Choose destination folder on Mac for photo import"

        if panel.runModal() == .OK, let targetDirURL = panel.url {
            for item in selectedItems {
                let dest = targetDirURL.appendingPathComponent(item.name)
                TransferManager.shared.enqueueDownload(
                    serial: device.id,
                    remotePath: item.path,
                    filename: item.name,
                    sizeBytes: item.sizeBytes,
                    destinationURL: dest,
                    isDirectory: false
                )
            }
            galleryMessage = "Queued import of \(selectedItems.count) photos to \(targetDirURL.lastPathComponent)"
            isGalleryError = false
        }
    }

    private func executeDeleteSelectedMedia() {
        guard let device = appState.selectedDevice else { return }
        let pathsToDelete = Array(selectedMediaPaths)
        guard !pathsToDelete.isEmpty else { return }

        Task {
            do {
                try await ADBManager.shared.deleteMultiple(serial: device.id, remotePaths: pathsToDelete)
                await MainActor.run {
                    self.selectedMediaPaths.removeAll()
                    self.galleryMessage = "Deleted \(pathsToDelete.count) item\(pathsToDelete.count == 1 ? "" : "s")"
                    self.isGalleryError = false
                    self.loadMedia()
                }
            } catch {
                await MainActor.run {
                    self.galleryMessage = "Delete failed: \(error.localizedDescription)"
                    self.isGalleryError = true
                }
            }
        }
    }
}

// MARK: - Photo Thumbnail Card View

private struct PhotoThumbnailCard: View {
    let item: PhotoItem
    let isSelected: Bool
    let serial: String

    @State private var thumbnailImage: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background & Thumbnail / Fallback Graphic
            ZStack {
                Color(NSColor.controlBackgroundColor)

                if let img = thumbnailImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                } else {
                    Image(systemName: item.isVideo ? "film.fill" : "photo.fill")
                        .font(.system(size: 28))
                        .foregroundColor(item.isVideo ? .purple.opacity(0.4) : .blue.opacity(0.4))
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
            )
            .task(id: item.path) {
                if item.isVideo { return }
                if let cached = MediaThumbnailCache.shared.thumbnail(for: item.path) {
                    self.thumbnailImage = cached
                    return
                }
                guard item.sizeBytes <= 25 * 1024 * 1024 else { return }
                do {
                    let data = try await ADBManager.shared.fetchMediaThumbnailData(serial: serial, remotePath: item.path)
                    if let thumb = createThumbnail(from: data, maxPixelSize: 320) {
                        MediaThumbnailCache.shared.setThumbnail(thumb, for: item.path)
                        await MainActor.run {
                            self.thumbnailImage = thumb
                        }
                    }
                } catch {
                    // Fallback to placeholder icon
                }
            }

            // Selection Checkmark Pill (top right)
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.black.opacity(0.3))
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(6)
                }
                Spacer()
            }

            // Bottom Caption Badge (Video or Filename)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                    }
                    Text(item.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65))
                .cornerRadius(4)
                .padding(6)
            }
        }
        .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.04), radius: 3, x: 0, y: 1)
    }
}
