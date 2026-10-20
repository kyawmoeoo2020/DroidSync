import Foundation

public enum TransferDirection: String, CaseIterable, Sendable {
    case download = "To Mac"
    case upload = "To Phone"

    public var systemImageName: String {
        switch self {
        case .download: return "arrow.down.circle.fill"
        case .upload: return "arrow.up.circle.fill"
        }
    }
}

public enum TransferStatus: String, CaseIterable, Sendable {
    case queued = "Queued"
    case transferring = "Transferring"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

public struct TransferTask: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let filename: String
    public let sourcePath: String
    public let destinationPath: String
    public let direction: TransferDirection
    public var status: TransferStatus
    public var totalBytes: Int64
    public var transferredBytes: Int64
    public var speedBytesPerSec: Double
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        filename: String,
        sourcePath: String,
        destinationPath: String,
        direction: TransferDirection,
        status: TransferStatus = .queued,
        totalBytes: Int64 = 0,
        transferredBytes: Int64 = 0,
        speedBytesPerSec: Double = 0.0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.direction = direction
        self.status = status
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.errorMessage = errorMessage
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(transferredBytes) / Double(totalBytes)))
    }

    public var formattedSpeed: String {
        guard speedBytesPerSec > 0 else { return "-- MB/s" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSec), countStyle: .file))/s"
    }

    public var formattedProgress: String {
        let transferred = ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(transferred) of \(total)"
    }
}
