import Foundation
import SwiftUI
import Combine

public enum NavigationSection: Hashable, Sendable {
    case dashboard
    case files(path: String)
    case photos
    case downloads
    case music
    case apps
    case storageLens
    case wirelessPair

    public var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .files: return "All Files"
        case .photos: return "Photos & DCIM"
        case .downloads: return "Downloads"
        case .music: return "Music"
        case .apps: return "Installed Apps"
        case .storageLens: return "Storage Lens"
        case .wirelessPair: return "Wireless Pairing"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .files: return "folder.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .downloads: return "arrow.down.circle.fill"
        case .music: return "music.note.list"
        case .apps: return "square.grid.2x2.fill"
        case .storageLens: return "chart.pie.fill"
        case .wirelessPair: return "wifi.circle.fill"
        }
    }

    @MainActor
    public static let primarySections: [NavigationSection] = [
        .dashboard,
        .files(path: "/sdcard"),
        .photos,
        .downloads,
        .music,
        .apps,
        .storageLens,
        .wirelessPair
    ]
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var connectedDevices: [Device] = []
    @Published public var selectedDevice: Device?
    @Published public var currentSection: NavigationSection = .dashboard

    // File Browser state
    @Published public var currentPath: String = "/sdcard"
    @Published public var filesInCurrentDirectory: [DeviceFile] = []
    @Published public var selectedFileIDs: Set<String> = []
    @Published public var lastSelectedFileID: String? = nil
    @Published public var isLoadingFiles: Bool = false
    @Published public var searchText: String = ""

    public var selectedFile: DeviceFile? {
        get {
            guard let id = selectedFileIDs.first else { return nil }
            return filesInCurrentDirectory.first { $0.id == id }
        }
        set {
            if let file = newValue {
                selectedFileIDs = [file.id]
                lastSelectedFileID = file.id
            } else {
                selectedFileIDs.removeAll()
                lastSelectedFileID = nil
            }
        }
    }

    public var selectedFiles: [DeviceFile] {
        filesInCurrentDirectory.filter { selectedFileIDs.contains($0.id) }
    }

    public var selectedFilesTotalSize: Int64 {
        selectedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    public var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedFilesTotalSize, countStyle: .file)
    }

    public var isAllSelected: Bool {
        !filteredFiles.isEmpty && filteredFiles.allSatisfy { selectedFileIDs.contains($0.id) }
    }

    public func toggleSelectAll() {
        if isAllSelected {
            selectedFileIDs.removeAll()
            lastSelectedFileID = nil
        } else {
            selectedFileIDs = Set(filteredFiles.map(\.id))
            lastSelectedFileID = filteredFiles.last?.id
        }
    }

    public func toggleSelection(for file: DeviceFile) {
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
            if lastSelectedFileID == file.id {
                lastSelectedFileID = selectedFileIDs.first
            }
        } else {
            selectedFileIDs.insert(file.id)
            lastSelectedFileID = file.id
        }
    }

    public func selectSingleFile(_ file: DeviceFile) {
        selectedFileIDs = [file.id]
        lastSelectedFileID = file.id
    }

    /// Selects a contiguous range of files from the last anchor item to the clicked item
    public func selectRange(to file: DeviceFile) {
        guard let anchorID = lastSelectedFileID,
              let anchorIdx = filteredFiles.firstIndex(where: { $0.id == anchorID }),
              let targetIdx = filteredFiles.firstIndex(where: { $0.id == file.id }) else {
            selectSingleFile(file)
            return
        }
        let lower = min(anchorIdx, targetIdx)
        let upper = max(anchorIdx, targetIdx)
        for i in lower...upper {
            selectedFileIDs.insert(filteredFiles[i].id)
        }
    }

    // Installed apps state
    @Published public var installedApps: [AppInfo] = []
    @Published public var appFilter: AppFilterType = .thirdParty
    @Published public var selectedApp: AppInfo?
    @Published public var installedPackages: [String] = []
    @Published public var isLoadingPackages: Bool = false

    // Status / Messages
    @Published public var statusMessage: String = "Ready"

    private var cancellables = Set<AnyCancellable>()
    private var scanTimer: Timer?

    public init() {
        startDevicePolling()
        setupTransferNotifications()
    }

    private func setupTransferNotifications() {
        NotificationCenter.default.publisher(for: .transferDidComplete)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                // Only reload files if an upload completed.
                // Avoid reloading on download completions to prevent wiping multi-selection and UI thrashing!
                if let dir = notification.object as? TransferDirection, dir == .upload {
                    self.loadFiles(at: self.currentPath)
                }
            }
            .store(in: &cancellables)
    }

    public func startDevicePolling() {
        refreshDevices()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
    }

    public func refreshDevices() {
        Task {
            let devices = await ADBManager.shared.scanDevices()
            self.connectedDevices = devices

            if self.selectedDevice == nil, let first = devices.first {
                self.selectedDevice = first
            } else if let current = self.selectedDevice, !devices.contains(where: { $0.id == current.id }) {
                self.selectedDevice = devices.first
            }
        }
    }

    public func navigateTo(path: String) {
        currentPath = path
        currentSection = .files(path: path)
        selectedFileIDs.removeAll()
        lastSelectedFileID = nil
        loadFiles(at: path)
    }

    public func loadFiles(at path: String) {
        guard let device = selectedDevice else { return }
        isLoadingFiles = true
        selectedFileIDs.removeAll()
        lastSelectedFileID = nil

        Task {
            do {
                let files = try await ADBManager.shared.listDirectory(serial: device.id, path: path)
                self.filesInCurrentDirectory = files
                self.currentPath = path
                self.isLoadingFiles = false
            } catch {
                self.statusMessage = "Failed to load directory: \(error.localizedDescription)"
                self.isLoadingFiles = false
            }
        }
    }

    public func loadPackages(filter: AppFilterType? = nil) {
        guard let device = selectedDevice else { return }
        let currentFilter = filter ?? appFilter
        if let f = filter {
            self.appFilter = f
        }
        isLoadingPackages = true

        Task {
            do {
                let apps = try await ADBManager.shared.listApps(serial: device.id, filter: currentFilter)
                self.installedApps = apps
                self.installedPackages = apps.map(\.packageName)
                self.isLoadingPackages = false
            } catch {
                self.isLoadingPackages = false
            }
        }
    }

    public var filteredFiles: [DeviceFile] {
        if searchText.isEmpty {
            return filesInCurrentDirectory
        }
        return filesInCurrentDirectory.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}
