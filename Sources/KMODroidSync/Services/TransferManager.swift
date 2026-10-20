import Foundation
import Combine

@MainActor
public final class TransferManager: ObservableObject {
    public static let shared = TransferManager()

    @Published public var tasks: [TransferTask] = []
    @Published public var isTransferring: Bool = false

    private init() {}

    public var activeTasks: [TransferTask] {
        tasks.filter { $0.status == .transferring || $0.status == .queued }
    }

    public var completedTasks: [TransferTask] {
        tasks.filter { $0.status == .completed }
    }

    public func enqueueDownload(
        serial: String,
        remotePath: String,
        filename: String,
        sizeBytes: Int64,
        destinationURL: URL
    ) {
        let task = TransferTask(
            filename: filename,
            sourcePath: remotePath,
            destinationPath: destinationURL.path,
            direction: .download,
            status: .queued,
            totalBytes: sizeBytes
        )

        tasks.insert(task, at: 0)
        processNext(serial: serial, taskID: task.id, localURL: destinationURL, remotePath: remotePath, direction: .download)
    }

    public func enqueueUpload(
        serial: String,
        localURL: URL,
        remoteDirectory: String
    ) {
        let filename = localURL.lastPathComponent
        let targetRemote = remoteDirectory.hasSuffix("/") ? "\(remoteDirectory)\(filename)" : "\(remoteDirectory)/\(filename)"
        let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0

        let task = TransferTask(
            filename: filename,
            sourcePath: localURL.path,
            destinationPath: targetRemote,
            direction: .upload,
            status: .queued,
            totalBytes: size
        )

        tasks.insert(task, at: 0)
        processNext(serial: serial, taskID: task.id, localURL: localURL, remotePath: targetRemote, direction: .upload)
    }

    private func processNext(
        serial: String,
        taskID: UUID,
        localURL: URL,
        remotePath: String,
        direction: TransferDirection
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .transferring
        isTransferring = true

        let startTime = Date()

        Task {
            do {
                if direction == .download {
                    try await ADBManager.shared.pullFile(serial: serial, remotePath: remotePath, localURL: localURL)
                } else {
                    try await ADBManager.shared.pushFile(serial: serial, localURL: localURL, remotePath: remotePath)
                }

                let elapsed = max(0.1, Date().timeIntervalSince(startTime))
                await MainActor.run {
                    if let idx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                        self.tasks[idx].status = .completed
                        self.tasks[idx].transferredBytes = self.tasks[idx].totalBytes
                        self.tasks[idx].speedBytesPerSec = Double(self.tasks[idx].totalBytes) / elapsed
                    }
                    self.updateTransferringState()
                }
            } catch {
                await MainActor.run {
                    if let idx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                        self.tasks[idx].status = .failed
                        self.tasks[idx].errorMessage = error.localizedDescription
                    }
                    self.updateTransferringState()
                }
            }
        }
    }

    private func updateTransferringState() {
        isTransferring = tasks.contains { $0.status == .transferring }
    }

    public func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
    }
}
