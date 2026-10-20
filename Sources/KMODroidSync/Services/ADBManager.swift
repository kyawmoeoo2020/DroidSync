import Foundation

public final class ADBManager: @unchecked Sendable {
    public static let shared = ADBManager()

    private var cachedAdbPath: String?

    public init() {}

    /// Automatically discovers ADB on macOS
    public func resolveAdbPath() -> String? {
        if let cached = cachedAdbPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedAdbPath = path
                return path
            }
        }

        // Try 'which adb' via shell
        let shellCheck = runProcess(executable: "/usr/bin/which", arguments: ["adb"])
        let output = shellCheck.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty && FileManager.default.isExecutableFile(atPath: output) {
            cachedAdbPath = output
            return output
        }

        return nil
    }

    /// Sets a manual custom ADB path
    public func setCustomAdbPath(_ path: String) {
        if FileManager.default.isExecutableFile(atPath: path) {
            cachedAdbPath = path
        }
    }

    /// Run any arbitrary process asynchronously
    @discardableResult
    public func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe

        if let env = environment {
            process.environment = env
        }

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
        } catch {
            return ""
        }
    }

    /// Execute an ADB command
    public func executeAdb(_ arguments: [String]) async throws -> String {
        guard let adb = resolveAdbPath() else {
            throw NSError(
                domain: "ADBManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "ADB not found. Please ensure Android SDK platform-tools is installed."]
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let output = self.runProcess(executable: adb, arguments: arguments)
                continuation.resume(returning: output)
            }
        }
    }

    /// Scan for connected devices
    public func scanDevices() async -> [Device] {
        guard let output = try? await executeAdb(["devices", "-l"]) else {
            return []
        }

        var devices: [Device] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices") || trimmed.hasPrefix("*") {
                continue
            }

            let parts = trimmed.split(separator: " ").map(String.init)
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let status = parts[1]

            guard status == "device" else { continue }

            // Parse model, product, device name from line
            var model = "Android Device"
            var manufacturer = "Generic"
            let connectionType: ConnectionType = serial.contains(":") ? .wifi : .usb

            for part in parts.dropFirst(2) {
                if part.hasPrefix("model:") {
                    model = part.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
                } else if part.hasPrefix("device:") {
                    manufacturer = part.replacingOccurrences(of: "device:", with: "").capitalized
                }
            }

            var device = Device(
                id: serial,
                name: model,
                manufacturer: manufacturer,
                model: model,
                platform: .android,
                connectionType: connectionType,
                osVersion: "Android",
                isConnected: true
            )

            // Populate hardware specs (battery, storage, OS)
            if let details = await fetchDeviceDetails(serial: serial) {
                device.osVersion = details.osVersion
                device.batteryLevel = details.batteryLevel
                device.isCharging = details.isCharging
                device.batteryTempCelsius = details.batteryTemp
                device.storage = details.storage
            }

            devices.append(device)
        }

        return devices
    }

    private struct QuickDetails {
        var osVersion: String
        var batteryLevel: Int
        var isCharging: Bool
        var batteryTemp: Double
        var storage: StorageInfo
    }

    private func fetchDeviceDetails(serial: String) async -> QuickDetails? {
        async let osRaw = executeAdb(["-s", serial, "shell", "getprop", "ro.build.version.release"])
        async let batteryRaw = executeAdb(["-s", serial, "shell", "dumpsys", "battery"])
        async let dfRaw = executeAdb(["-s", serial, "shell", "df", "/sdcard"])

        let os = (try? await osRaw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let batteryStr = (try? await batteryRaw) ?? ""
        let dfStr = (try? await dfRaw) ?? ""

        var level = 100
        var charging = false
        var temp = 25.0

        for line in batteryStr.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("level:") {
                level = Int(trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "100") ?? 100
            } else if trimmed.hasPrefix("status:") {
                let statusVal = Int(trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                charging = (statusVal == 2 || statusVal == 5) // Charging or Full
            } else if trimmed.hasPrefix("temperature:") {
                let rawTemp = Double(trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "250") ?? 250
                temp = rawTemp / 10.0
            }
        }

        var storage = StorageInfo()
        let dfLines = dfStr.components(separatedBy: .newlines)
        if dfLines.count > 1 {
            let parts = dfLines[1].split(whereSeparator: \.isWhitespace)
            if parts.count >= 4 {
                // 1K-blocks format
                let total1k = Int64(parts[1]) ?? 0
                let free1k = Int64(parts[3]) ?? 0
                storage.totalBytes = total1k * 1024
                storage.storageFreeBytes(free1k * 1024)
            }
        }

        return QuickDetails(
            osVersion: os.isEmpty ? "Android" : "Android \(os)",
            batteryLevel: level,
            isCharging: charging,
            batteryTemp: temp,
            storage: storage
        )
    }

    /// List directory contents
    public func listDirectory(serial: String, path: String) async throws -> [DeviceFile] {
        let cleanPath = path.isEmpty ? "/sdcard" : path
        // Using ls -laL with stat fallback
        let rawOutput = try await executeAdb(["-s", serial, "shell", "ls", "-laL", cleanPath])
        var files: [DeviceFile] = []

        let lines = rawOutput.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total ") { continue }

            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 7 else { continue }

            let permissions = tokens[0]
            let isDir = permissions.hasPrefix("d")

            // Typically: permissions, links, owner, group, size, date, time, name
            var filename = ""
            var size: Int64 = 0

            if tokens.count >= 8 {
                size = Int64(tokens[4]) ?? 0
                filename = tokens.dropFirst(7).joined(separator: " ")
            } else {
                filename = tokens.last ?? ""
            }

            if filename == "." || filename == ".." {
                continue
            }

            let fullPath = cleanPath.hasSuffix("/") ? "\(cleanPath)\(filename)" : "\(cleanPath)/\(filename)"

            let file = DeviceFile(
                name: filename,
                path: fullPath,
                isDirectory: isDir,
                sizeBytes: size,
                modifiedDate: Date(),
                permissions: permissions
            )
            files.append(file)
        }

        // Sort: directories first, then alphabetical
        return files.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Pull file from Android to local Mac path
    public func pullFile(serial: String, remotePath: String, localURL: URL) async throws {
        _ = try await executeAdb(["-s", serial, "pull", remotePath, localURL.path])
    }

    /// Push file from local Mac to Android path
    public func pushFile(serial: String, localURL: URL, remotePath: String) async throws {
        _ = try await executeAdb(["-s", serial, "push", localURL.path, remotePath])
    }

    /// Delete file or directory on device
    public func delete(serial: String, remotePath: String) async throws {
        _ = try await executeAdb(["-s", serial, "shell", "rm", "-rf", remotePath])
    }

    /// Create new folder
    public func createDirectory(serial: String, remotePath: String) async throws {
        _ = try await executeAdb(["-s", serial, "shell", "mkdir", "-p", remotePath])
    }

    /// Install APK
    public func installApk(serial: String, apkURL: URL) async throws -> String {
        return try await executeAdb(["-s", serial, "install", "-r", apkURL.path])
    }

    /// List 3rd party installed apps
    public func listInstalledPackages(serial: String) async throws -> [String] {
        let output = try await executeAdb(["-s", serial, "shell", "pm", "list", "packages", "-3"])
        return output.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Pair via Wi-Fi ADB (Android 11+)
    public func pairWireless(host: String, port: Int, code: String) async throws -> String {
        return try await executeAdb(["pair", "\(host):\(port)", code])
    }

    /// Connect via Wi-Fi ADB
    public func connectWireless(host: String, port: Int) async throws -> String {
        return try await executeAdb(["connect", "\(host):\(port)"])
    }
}

private extension StorageInfo {
    mutating func storageFreeBytes(_ free: Int64) {
        self.freeBytes = free
    }
}
