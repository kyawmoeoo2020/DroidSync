import Foundation

public struct StorageVolume: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isRemovable: Bool
    public var totalBytes: Int64
    public var freeBytes: Int64

    public init(path: String, name: String, isRemovable: Bool, totalBytes: Int64 = 0, freeBytes: Int64 = 0) {
        self.path = path
        self.name = name
        self.isRemovable = isRemovable
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }

    public var formattedFree: String {
        guard totalBytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
    }

    public var formattedTotal: String {
        guard totalBytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var formattedUsed: String {
        guard totalBytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }

    public var iconSystemName: String {
        isRemovable ? "externaldrive.fill" : "internaldrive.fill"
    }
}

public struct BackupPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let remotePath: String
    public let defaultChecked: Bool

    public init(id: String, name: String, icon: String, remotePath: String, defaultChecked: Bool) {
        self.id = id
        self.name = name
        self.icon = icon
        self.remotePath = remotePath
        self.defaultChecked = defaultChecked
    }

    public static let defaults: [BackupPreset] = [
        BackupPreset(id: "camera", name: "Camera Photos & Videos", icon: "camera.fill", remotePath: "/sdcard/DCIM", defaultChecked: true),
        BackupPreset(id: "pictures", name: "Pictures & Screenshots", icon: "photo.stack.fill", remotePath: "/sdcard/Pictures", defaultChecked: true),
        BackupPreset(id: "download", name: "Downloads", icon: "arrow.down.circle.fill", remotePath: "/sdcard/Download", defaultChecked: true),
        BackupPreset(id: "documents", name: "Documents", icon: "doc.text.fill", remotePath: "/sdcard/Documents", defaultChecked: true),
        BackupPreset(id: "music", name: "Music & Audio", icon: "music.note.list", remotePath: "/sdcard/Music", defaultChecked: false),
        BackupPreset(id: "movies", name: "Movies & Recordings", icon: "film.fill", remotePath: "/sdcard/Movies", defaultChecked: false)
    ]
}
