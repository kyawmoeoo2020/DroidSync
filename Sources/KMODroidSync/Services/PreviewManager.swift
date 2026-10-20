import Foundation
import QuickLookUI

@MainActor
public final class PreviewManager: ObservableObject {
    public static let shared = PreviewManager()

    @Published public var previewURL: URL?
    @Published public var isPreviewing: Bool = false
    @Published public var isLoading: Bool = false

    private let cacheDir: URL

    private init() {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("KMODroidSyncPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        self.cacheDir = temp
    }

    public func quickLook(file: DeviceFile, serial: String) async {
        guard !file.isDirectory else { return }

        isLoading = true
        let localTempURL = cacheDir.appendingPathComponent(file.name)

        do {
            try await ADBManager.shared.pullFile(serial: serial, remotePath: file.path, localURL: localTempURL)
            self.previewURL = localTempURL
            self.isPreviewing = true
        } catch {
            print("Preview fetch failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    public func closePreview() {
        isPreviewing = false
        previewURL = nil
    }
}
