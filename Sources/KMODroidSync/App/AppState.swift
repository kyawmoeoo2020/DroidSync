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
    @Published public var selectedFile: DeviceFile?
    @Published public var isLoadingFiles: Bool = false
    @Published public var searchText: String = ""

    // Installed apps state
    @Published public var installedPackages: [String] = []
    @Published public var isLoadingPackages: Bool = false

    // Status / Messages
    @Published public var statusMessage: String = "Ready"

    private var cancellables = Set<AnyCancellable>()
    private var scanTimer: Timer?

    public init() {
        startDevicePolling()
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
        loadFiles(at: path)
    }

    public func loadFiles(at path: String) {
        guard let device = selectedDevice else { return }
        isLoadingFiles = true

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

    public func loadPackages() {
        guard let device = selectedDevice else { return }
        isLoadingPackages = true

        Task {
            do {
                let packages = try await ADBManager.shared.listInstalledPackages(serial: device.id)
                self.installedPackages = packages
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
