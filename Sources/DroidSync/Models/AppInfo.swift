import Foundation

public enum AppFilterType: String, CaseIterable, Identifiable, Sendable {
    case thirdParty = "User Apps"
    case all = "All Apps"
    case system = "System Apps"
    case disabled = "Disabled"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .thirdParty: return "person.crop.circle"
        case .all: return "square.grid.2x2"
        case .system: return "gearshape.2"
        case .disabled: return "snowflake"
        }
    }
}

public struct AppInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { packageName }
    public let displayName: String
    public let packageName: String
    public let apkPath: String
    public var versionName: String
    public var versionCode: String
    public var isSystemApp: Bool
    public var isEnabled: Bool
    public var sizeBytes: Int64

    public init(
        packageName: String,
        displayName: String? = nil,
        apkPath: String = "",
        versionName: String = "",
        versionCode: String = "",
        isSystemApp: Bool = false,
        isEnabled: Bool = true,
        sizeBytes: Int64 = 0
    ) {
        self.packageName = packageName
        self.displayName = displayName ?? Self.formatDisplayName(packageName: packageName)
        self.apkPath = apkPath
        self.versionName = versionName
        self.versionCode = versionCode
        self.isSystemApp = isSystemApp
        self.isEnabled = isEnabled
        self.sizeBytes = sizeBytes
    }

    public var formattedSize: String {
        guard sizeBytes > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public static func formatDisplayName(packageName: String) -> String {
        // e.g. "com.spotify.music" -> "Spotify Music"
        // e.g. "org.mozilla.firefox" -> "Firefox"
        // e.g. "com.google.android.youtube" -> "YouTube"
        let segments = packageName.split(separator: ".").map(String.init)
        guard let last = segments.last else { return packageName }

        // Common known overrides
        let lowerLast = last.lowercased()
        if lowerLast == "youtube" { return "YouTube" }
        if lowerLast == "chrome" { return "Google Chrome" }
        if lowerLast == "whatsapp" { return "WhatsApp" }
        if lowerLast == "instagram" { return "Instagram" }
        if lowerLast == "twitter" || lowerLast == "x" { return "X (Twitter)" }
        if lowerLast == "spotify" { return "Spotify" }
        if lowerLast == "firefox" { return "Firefox" }
        if lowerLast == "telegram" || packageName.contains("telegram") { return "Telegram" }

        // Clean up last segment or last two segments
        if segments.count >= 2 {
            let secondLast = segments[segments.count - 2]
            if ["android", "apps", "app", "mobile", "client", "corp", "inc"].contains(secondLast.lowercased()) {
                return capitalizeWords(last)
            }
            if ["google", "microsoft", "samsung", "xiaomi", "facebook", "amazon"].contains(secondLast.lowercased()) {
                return "\(secondLast.capitalized) \(capitalizeWords(last))"
            }
        }

        return capitalizeWords(last)
    }

    private static func capitalizeWords(_ str: String) -> String {
        let parts = str.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: " ")
        return parts.map { $0.capitalized }.joined(separator: " ")
    }
}

public struct AppDetailedInfo: Sendable {
    public var packageName: String
    public var versionName: String
    public var versionCode: String
    public var targetSdk: String
    public var minSdk: String
    public var firstInstallTime: String
    public var lastUpdateTime: String
    public var apkPath: String
    public var permissions: [String]

    public init(
        packageName: String,
        versionName: String = "",
        versionCode: String = "",
        targetSdk: String = "",
        minSdk: String = "",
        firstInstallTime: String = "",
        lastUpdateTime: String = "",
        apkPath: String = "",
        permissions: [String] = []
    ) {
        self.packageName = packageName
        self.versionName = versionName
        self.versionCode = versionCode
        self.targetSdk = targetSdk
        self.minSdk = minSdk
        self.firstInstallTime = firstInstallTime
        self.lastUpdateTime = lastUpdateTime
        self.apkPath = apkPath
        self.permissions = permissions
    }
}
