import Foundation

public enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case android = "Android"
}

public enum ConnectionType: String, Codable, CaseIterable, Sendable {
    case usb = "USB"
    case wifi = "Wi-Fi"
}

public struct StorageInfo: Equatable, Hashable, Sendable {
    public var totalBytes: Int64
    public var freeBytes: Int64
    public var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public init(totalBytes: Int64 = 0, freeBytes: Int64 = 0) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }

    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }

    public var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
    }
}

public struct Device: Identifiable, Equatable, Hashable, Sendable {
    public let id: String // Serial or IP:Port
    public var name: String // e.g. "Pixel 8 Pro"
    public var manufacturer: String // e.g. "Google"
    public var model: String
    public var platform: DevicePlatform
    public var connectionType: ConnectionType
    public var osVersion: String // e.g. "Android 15"
    public var batteryLevel: Int // 0 - 100
    public var isCharging: Bool
    public var batteryTempCelsius: Double
    public var storage: StorageInfo
    public var isConnected: Bool

    public init(
        id: String,
        name: String = "Android Device",
        manufacturer: String = "Generic",
        model: String = "Unknown",
        platform: DevicePlatform = .android,
        connectionType: ConnectionType = .usb,
        osVersion: String = "Android",
        batteryLevel: Int = 100,
        isCharging: Bool = false,
        batteryTempCelsius: Double = 25.0,
        storage: StorageInfo = StorageInfo(),
        isConnected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.platform = platform
        self.connectionType = connectionType
        self.osVersion = osVersion
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.batteryTempCelsius = batteryTempCelsius
        self.storage = storage
        self.isConnected = isConnected
    }
}
