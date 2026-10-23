import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
    case folder
    case image
    case video
    case audio
    case document
    case apk
    case archive
    case other

    public var systemImageName: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .document: return "doc.text.fill"
        case .apk: return "app.badge.fill"
        case .archive: return "archivebox.fill"
        case .other: return "doc.fill"
        }
    }
}

public struct DeviceFile: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let modifiedDate: Date?
    public let permissions: String
    public let category: FileCategory

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        sizeBytes: Int64 = 0,
        modifiedDate: Date? = nil,
        permissions: String = ""
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
        self.permissions = permissions
        self.category = DeviceFile.determineCategory(name: name, isDirectory: isDirectory)
    }

    public var formattedSize: String {
        if isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var formattedDate: String {
        guard let date = modifiedDate else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func determineCategory(name: String, isDirectory: Bool) -> FileCategory {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp":
            return .image
        case "mp4", "mkv", "mov", "avi", "webm", "flv", "3gp":
            return .video
        case "mp3", "m4a", "flac", "wav", "ogg", "aac", "opus":
            return .audio
        case "pdf", "txt", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "md", "csv", "json":
            return .document
        case "apk", "xapk", "apks":
            return .apk
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return .archive
        default:
            return .other
        }
    }
}
