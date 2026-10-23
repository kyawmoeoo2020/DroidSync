import Foundation

public struct StorageFolderItem: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public var percentageOfParent: Double

    public init(name: String, path: String, sizeBytes: Int64, percentageOfParent: Double = 0.0) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.percentageOfParent = percentageOfParent
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct StorageLargeFile: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let category: FileCategory

    public init(name: String, path: String, sizeBytes: Int64) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.category = DeviceFile.determineCategory(name: name, isDirectory: false)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
