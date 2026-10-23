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
    public let isDirectory: Bool
    public var status: TransferStatus
    public var totalBytes: Int64
    public var transferredBytes: Int64
    public var speedBytesPerSec: Double
    public var currentSubfile: String?
    public var etaSeconds: TimeInterval?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        filename: String,
        sourcePath: String,
        destinationPath: String,
        direction: TransferDirection,
        isDirectory: Bool = false,
        status: TransferStatus = .queued,
        totalBytes: Int64 = 0,
        transferredBytes: Int64 = 0,
        speedBytesPerSec: Double = 0.0,
        currentSubfile: String? = nil,
        etaSeconds: TimeInterval? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.direction = direction
        self.isDirectory = isDirectory
        self.status = status
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.currentSubfile = currentSubfile
        self.etaSeconds = etaSeconds
        self.errorMessage = errorMessage
    }

    public var progressFraction: Double {
        if status == .completed { return 1.0 }
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(transferredBytes) / Double(totalBytes)))
    }

    public var percentageText: String {
        let pct = Int((progressFraction * 100).rounded())
        return "\(pct)%"
    }

    public var formattedSpeed: String {
        guard speedBytesPerSec > 0 else { return "-- MB/s" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSec), countStyle: .file))/s"
    }

    public var formattedProgress: String {
        let transferred = ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
        if totalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(transferred) of \(total)"
        } else if transferredBytes > 0 {
            return transferred
        } else {
            return "0 bytes"
        }
    }

    public var formattedETA: String {
        guard let eta = etaSeconds, eta.isFinite, eta > 0 else { return "" }
        if eta < 1 { return "< 1s left" }
        let totalSec = Int(eta.rounded())
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let seconds = totalSec % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s left"
        } else {
            return "\(seconds)s left"
        }
    }
}
