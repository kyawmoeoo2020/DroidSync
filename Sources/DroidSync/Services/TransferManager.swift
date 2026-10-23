import Foundation
import Combine

public extension Notification.Name {
    static let transferDidComplete = Notification.Name("DroidSync.transferDidComplete")
}

@MainActor
public final class TransferManager: ObservableObject {
    public static let shared = TransferManager()

    @Published public var tasks: [TransferTask] = []
    @Published public var isTransferring: Bool = false

    private struct TransferRequest {
        let taskID: UUID
        let serial: String
        let localURL: URL
        let remotePath: String
        let direction: TransferDirection
        let isDirectory: Bool
    }

    private var pendingRequests: [TransferRequest] = []
    private var isProcessingQueue: Bool = false
    private var activeExecutionTask: Task<Void, Never>?
    private var currentActiveTaskId: UUID?
    private var lastUIUpdateTime: TimeInterval = 0

    private init() {}

    public var activeTasks: [TransferTask] {
        tasks.filter { $0.status == .transferring || $0.status == .queued }
    }

    public var completedTasks: [TransferTask] {
        tasks.filter { $0.status == .completed }
    }

    /// Enqueue a download from Android to Mac
    public func enqueueDownload(
        serial: String,
        remotePath: String,
        filename: String,
        sizeBytes: Int64,
        destinationURL: URL,
        isDirectory: Bool = false
    ) {
        let task = TransferTask(
            filename: filename,
            sourcePath: remotePath,
            destinationPath: destinationURL.path,
            direction: .download,
            isDirectory: isDirectory,
            status: .queued,
            totalBytes: sizeBytes
        )

        tasks.insert(task, at: 0)
        pendingRequests.append(TransferRequest(
            taskID: task.id,
            serial: serial,
            localURL: destinationURL,
            remotePath: remotePath,
            direction: .download,
            isDirectory: isDirectory
        ))

        processNextInQueue()
    }

    /// Enqueue an upload from Mac to Android
    public func enqueueUpload(
        serial: String,
        localURL: URL,
        remoteDirectory: String
    ) {
        let filename = localURL.lastPathComponent
        let targetRemote = remoteDirectory.hasSuffix("/") ? "\(remoteDirectory)\(filename)" : "\(remoteDirectory)/\(filename)"
        let size = Self.calculateLocalSize(url: localURL)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir)

        let task = TransferTask(
            filename: filename,
            sourcePath: localURL.path,
            destinationPath: targetRemote,
            direction: .upload,
            isDirectory: isDir.boolValue,
            status: .queued,
            totalBytes: size
        )

        tasks.insert(task, at: 0)
        pendingRequests.append(TransferRequest(
            taskID: task.id,
            serial: serial,
            localURL: localURL,
            remotePath: targetRemote,
            direction: .upload,
            isDirectory: isDir.boolValue
        ))

        processNextInQueue()
    }

    /// Calculates total size of a local file or recursive directory
    public static func calculateLocalSize(url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   vals.isDirectory == false {
                    total += Int64(vals.fileSize ?? 0)
                }
            }
        }
        return total
    }

    /// Cancels a specific transfer task
    public func cancelTask(id: UUID) {
        if currentActiveTaskId == id {
            activeExecutionTask?.cancel()
            ADBManager.shared.cancelActiveTransfer()
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].status = .cancelled
                tasks[idx].errorMessage = "Cancelled by user"
                tasks[idx].etaSeconds = nil
            }
        } else {
            pendingRequests.removeAll { $0.taskID == id }
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].status = .cancelled
                tasks[idx].errorMessage = "Cancelled by user"
                tasks[idx].etaSeconds = nil
            }
        }
        updateTransferringState()
    }

    /// Cancels all active and queued transfers
    public func cancelAll() {
        pendingRequests.removeAll()
        for idx in tasks.indices {
            if tasks[idx].status == .queued {
                tasks[idx].status = .cancelled
                tasks[idx].errorMessage = "Cancelled by user"
                tasks[idx].etaSeconds = nil
            }
        }
        if let currentId = currentActiveTaskId {
            cancelTask(id: currentId)
        }
    }

    /// Clears completed/failed/cancelled tasks
    public func clearCompleted() {
        tasks.removeAll { $0.status == .completed || $0.status == .cancelled || $0.status == .failed }
    }

    // MARK: - Queue Processor

    private func processNextInQueue() {
        guard !isProcessingQueue else { return }
        guard let next = pendingRequests.first else {
            isTransferring = false
            return
        }

        guard let idx = tasks.firstIndex(where: { $0.id == next.taskID }) else {
            pendingRequests.removeFirst()
            processNextInQueue()
            return
        }

        if tasks[idx].status == .cancelled {
            pendingRequests.removeFirst()
            processNextInQueue()
            return
        }

        isProcessingQueue = true
        isTransferring = true
        tasks[idx].status = .transferring
        currentActiveTaskId = next.taskID

        activeExecutionTask = Task { [weak self] in
            guard let self = self else { return }
            await self.executeTransfer(request: next)
        }
    }

    private func executeTransfer(request: TransferRequest) async {
        let taskID = request.taskID
        let serial = request.serial
        let localURL = request.localURL
        let remotePath = request.remotePath
        let direction = request.direction

        var initialTotalBytes: Int64 = 0
        if let current = tasks.first(where: { $0.id == taskID }) {
            initialTotalBytes = current.totalBytes
        }

        if direction == .download && request.isDirectory {
            let remoteSize = await ADBManager.shared.getRemotePathSize(serial: serial, path: remotePath)
            if remoteSize > 0 {
                initialTotalBytes = remoteSize
                if let idx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                    self.tasks[idx].totalBytes = remoteSize
                }
            }
        }

        do {
            if direction == .download {
                try await ADBManager.shared.pullFileWithProgress(
                    serial: serial,
                    remotePath: remotePath,
                    localURL: localURL,
                    totalBytes: initialTotalBytes
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.handleProgressUpdate(taskID: taskID, progress: progress)
                    }
                }
            } else {
                try await ADBManager.shared.pushFileWithProgress(
                    serial: serial,
                    localURL: localURL,
                    remotePath: remotePath,
                    totalBytes: initialTotalBytes
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.handleProgressUpdate(taskID: taskID, progress: progress)
                    }
                }
            }

            if let idx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                self.tasks[idx].status = .completed
                if self.tasks[idx].totalBytes > 0 {
                    self.tasks[idx].transferredBytes = self.tasks[idx].totalBytes
                }
                self.tasks[idx].etaSeconds = nil
            }
            NotificationCenter.default.post(name: .transferDidComplete, object: direction)

        } catch is CancellationError {
            if let idx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                self.tasks[idx].status = .cancelled
                self.tasks[idx].errorMessage = "Cancelled by user"
                self.tasks[idx].etaSeconds = nil
            }
        } catch {
            if let idx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                if self.tasks[idx].status != .cancelled {
                    self.tasks[idx].status = .failed
                    self.tasks[idx].errorMessage = error.localizedDescription
                    self.tasks[idx].etaSeconds = nil
                }
            }
        }

        self.currentActiveTaskId = nil
        self.activeExecutionTask = nil
        self.pendingRequests.removeAll { $0.taskID == taskID }
        self.isProcessingQueue = false
        self.updateTransferringState()
        self.processNextInQueue()
    }

    private func handleProgressUpdate(
        taskID: UUID,
        progress: FileTransferProgress
    ) {
        let now = Date().timeIntervalSince1970
        let isDone = (progress.percentage ?? 0) >= 100.0
        if !isDone && (now - lastUIUpdateTime < 0.06) {
            return
        }
        lastUIUpdateTime = now

        guard let idx = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[idx].status == .transferring || tasks[idx].status == .completed else { return }

        if progress.totalBytes > 0 {
            tasks[idx].totalBytes = progress.totalBytes
        }
        tasks[idx].transferredBytes = progress.transferredBytes
        tasks[idx].speedBytesPerSec = progress.speedBytesPerSec
        tasks[idx].etaSeconds = progress.etaSeconds
        if let subfile = progress.currentSubfile {
            tasks[idx].currentSubfile = subfile
        }
    }

    private func updateTransferringState() {
        isTransferring = tasks.contains { $0.status == .transferring }
    }
}
