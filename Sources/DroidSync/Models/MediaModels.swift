import Foundation

public enum MediaSource: String, CaseIterable, Identifiable, Sendable {
    case all = "All Media"
    case camera = "Camera (DCIM)"
    case pictures = "Pictures"
    case screenshots = "Screenshots"
    case movies = "Videos"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .camera: return "camera.fill"
        case .pictures: return "photo.stack"
        case .screenshots: return "iphone"
        case .movies: return "film"
        }
    }

    public var searchPaths: [String] {
        switch self {
        case .all:
            return ["/sdcard/DCIM", "/sdcard/Pictures"]
        case .camera:
            return ["/sdcard/DCIM/Camera", "/sdcard/DCIM"]
        case .pictures:
            return ["/sdcard/Pictures"]
        case .screenshots:
            return ["/sdcard/Pictures/Screenshots", "/sdcard/DCIM/Screenshots"]
        case .movies:
            return ["/sdcard/Movies", "/sdcard/DCIM/Camera"]
        }
    }
}

public struct PhotoItem: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let dateModified: Date
    public let isVideo: Bool

    public init(name: String, path: String, sizeBytes: Int64, dateModified: Date = Date(), isVideo: Bool = false) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.dateModified = dateModified
        self.isVideo = isVideo
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateModified)
    }

    public var sectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(dateModified) {
            return "Today"
        } else if calendar.isDateInYesterday(dateModified) {
            return "Yesterday"
        } else if calendar.isDate(dateModified, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else if calendar.isDate(dateModified, equalTo: Date(), toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: dateModified)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: dateModified)
        }
    }
}
