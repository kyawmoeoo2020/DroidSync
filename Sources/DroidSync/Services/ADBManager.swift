import Foundation
import Darwin
import os
import AppKit

public struct FileTransferProgress: Sendable {
    public var percentage: Double?
    public var transferredBytes: Int64
    public var totalBytes: Int64
    public var speedBytesPerSec: Double
    public var currentSubfile: String?
    public var etaSeconds: TimeInterval?

    public init(
        percentage: Double? = nil,
        transferredBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        speedBytesPerSec: Double = 0,
        currentSubfile: String? = nil,
        etaSeconds: TimeInterval? = nil
    ) {
        self.percentage = percentage
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.currentSubfile = currentSubfile
        self.etaSeconds = etaSeconds
    }
}

private final class ActiveProcessHolder: @unchecked Sendable {
    private var process: Process?
    private var isTerminatedByUser: Bool = false
    private let lock = NSLock()

    func set(_ proc: Process?) {
        lock.withLock {
            self.process = proc
            if proc == nil {
                self.isTerminatedByUser = false
            }
        }
    }

    func terminate() {
        lock.withLock {
            self.isTerminatedByUser = true
            if let p = self.process, p.isRunning {
                p.terminate()
            }
        }
    }

    var wasCancelled: Bool {
        lock.withLock { isTerminatedByUser }
    }
}

public final class ADBManager: @unchecked Sendable {
    public static let shared = ADBManager()

    private var cachedAdbPath: String?
    private let activeProcessHolder = ActiveProcessHolder()

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

    public struct ProcessExecutionResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32

        public var combinedOutput: String {
            if stdout.isEmpty { return stderr }
            if stderr.isEmpty { return stdout }
            return "\(stdout)\n\(stderr)"
        }
    }

    /// Run any arbitrary process asynchronously with full stdout/stderr capture
    public func runProcessDetailed(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> ProcessExecutionResult {
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

        final class PipeDataBox: @unchecked Sendable {
            var data = Data()
        }
        let outBox = PipeDataBox()
        let errBox = PipeDataBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBox.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
            group.wait()
            process.waitUntilExit()

            let stdoutStr = String(data: outBox.data, encoding: .utf8) ?? ""
            let stderrStr = String(data: errBox.data, encoding: .utf8) ?? ""
            return ProcessExecutionResult(stdout: stdoutStr, stderr: stderrStr, exitCode: process.terminationStatus)
        } catch {
            return ProcessExecutionResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }
    }

    /// Run any arbitrary process asynchronously
    @discardableResult
    public func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> String {
        let res = runProcessDetailed(executable: executable, arguments: arguments, environment: environment)
        if !res.stdout.isEmpty {
            return res.stdout
        }
        return res.stderr
    }

    /// Execute an ADB command with detailed status
    public func executeAdbDetailed(_ arguments: [String]) async throws -> ProcessExecutionResult {
        guard let adb = resolveAdbPath() else {
            throw NSError(
                domain: "ADBManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "ADB not found. Please ensure Android SDK platform-tools is installed."]
            )
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let res = self.runProcessDetailed(executable: adb, arguments: arguments)
                continuation.resume(returning: res)
            }
        }
    }

    /// Execute an ADB command
    public func executeAdb(_ arguments: [String]) async throws -> String {
        let res = try await executeAdbDetailed(arguments)
        if !res.stdout.isEmpty {
            return res.stdout
        }
        return res.stderr
    }

    /// Execute an ADB command and capture binary data from stdout
    public func executeAdbBinary(_ arguments: [String]) async throws -> Data {
        guard let adb = resolveAdbPath() else {
            throw NSError(
                domain: "ADBManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "ADB not found. Please ensure Android SDK platform-tools is installed."]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: adb)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = errorPipe

                final class BinaryBox: @unchecked Sendable {
                    var data = Data()
                    var errData = Data()
                }
                let box = BinaryBox()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    box.errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try process.run()
                    group.wait()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: box.data)
                    } else {
                        let errString = String(data: box.errData, encoding: .utf8) ?? "Command failed with code \(process.terminationStatus)"
                        continuation.resume(throwing: NSError(
                            domain: "ADBManager",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errString]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
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
                charging = (statusVal == 2 || statusVal == 5)
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
                let total1k = Int64(parts[1]) ?? 0
                let free1k = Int64(parts[3]) ?? 0
                storage.totalBytes = total1k * 1024
                storage.freeBytes = free1k * 1024
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

        return files.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Query the size of a remote file or folder in bytes using du -sk
    public func getRemotePathSize(serial: String, path: String) async -> Int64 {
        let quoted = "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
        guard let output = try? await executeAdb(["-s", serial, "shell", "du", "-sk", quoted]) else {
            return 0
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        if let first = parts.first, let kb = Int64(first) {
            return kb * 1024
        }
        return 0
    }

    /// Cancels currently running transfer process
    public func cancelActiveTransfer() {
        activeProcessHolder.terminate()
    }

    /// Pull file from Android to local Mac path with realtime progress reporting
    public func pullFileWithProgress(
        serial: String,
        remotePath: String,
        localURL: URL,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (FileTransferProgress) -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try await self.runTransferWithPTY(
                arguments: ["-s", serial, "pull", remotePath, localURL.path],
                direction: .download,
                localURL: localURL,
                totalBytes: totalBytes,
                onProgress: onProgress
            )
        } onCancel: {
            self.cancelActiveTransfer()
        }
    }

    /// Push file from local Mac to Android path with realtime progress reporting
    public func pushFileWithProgress(
        serial: String,
        localURL: URL,
        remotePath: String,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (FileTransferProgress) -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try await self.runTransferWithPTY(
                arguments: ["-s", serial, "push", localURL.path, remotePath],
                direction: .upload,
                localURL: localURL,
                totalBytes: totalBytes,
                onProgress: onProgress
            )
        } onCancel: {
            self.cancelActiveTransfer()
        }
    }

    /// Pull file from Android to local Mac path (backward-compatible convenience)
    public func pullFile(serial: String, remotePath: String, localURL: URL) async throws {
        try await pullFileWithProgress(serial: serial, remotePath: remotePath, localURL: localURL, totalBytes: 0, onProgress: { _ in })
    }

    /// Push file from local Mac to Android path (backward-compatible convenience)
    public func pushFile(serial: String, localURL: URL, remotePath: String) async throws {
        try await pushFileWithProgress(serial: serial, localURL: localURL, remotePath: remotePath, totalBytes: 0, onProgress: { _ in })
    }

    // MARK: - Internal PTY Execution & Progress Engine

    private func runTransferWithPTY(
        arguments: [String],
        direction: TransferDirection,
        localURL: URL,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (FileTransferProgress) -> Void
    ) async throws {
        guard let adb = resolveAdbPath() else {
            throw NSError(
                domain: "ADBManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "ADB not found. Please ensure Android SDK platform-tools is installed."]
            )
        }

        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            try await runTransferFallback(
                adb: adb,
                arguments: arguments,
                direction: direction,
                localURL: localURL,
                totalBytes: totalBytes,
                onProgress: onProgress
            )
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = arguments
        proc.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardError = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        proc.environment = env

        activeProcessHolder.set(proc)

        defer {
            activeProcessHolder.set(nil)
            close(master)
        }

        do {
            try proc.run()
        } catch {
            close(slave)
            throw error
        }

        close(slave)

        let startTime = Date()
        let isPull = (direction == .download)

        struct SpeedSample {
            let time: Date
            let bytes: Int64
        }

        struct PTYState {
            var samples: [SpeedSample]
            var knownTotalBytes: Int64
            var lastReportedBytes: Int64
            var lastReportedPct: Double
            var finalSpeed: Double
            var finalBytes: Int64
        }

        let transferLock = OSAllocatedUnfairLock(initialState: PTYState(
            samples: [SpeedSample(time: startTime, bytes: 0)],
            knownTotalBytes: totalBytes,
            lastReportedBytes: 0,
            lastReportedPct: 0.0,
            finalSpeed: 0,
            finalBytes: 0
        ))

        func computeSpeed(currentBytes: Int64) -> (speed: Double, eta: TimeInterval?) {
            transferLock.withLock { s in
                let now = Date()
                s.samples.append(SpeedSample(time: now, bytes: currentBytes))
                s.samples.removeAll { now.timeIntervalSince($0.time) > 1.2 }

                guard let first = s.samples.first, let last = s.samples.last, s.samples.count >= 2 else {
                    let totalElapsed = max(0.05, now.timeIntervalSince(startTime))
                    let avg = Double(currentBytes) / totalElapsed
                    return (avg, nil)
                }
                let timeDiff = last.time.timeIntervalSince(first.time)
                guard timeDiff > 0.05 else {
                    let totalElapsed = max(0.05, now.timeIntervalSince(startTime))
                    return (Double(currentBytes) / totalElapsed, nil)
                }
                let bytesDiff = max(0, last.bytes - first.bytes)
                let speed = Double(bytesDiff) / timeDiff

                var eta: TimeInterval? = nil
                if s.knownTotalBytes > currentBytes && speed > 0 {
                    eta = Double(s.knownTotalBytes - currentBytes) / speed
                }
                return (speed, eta)
            }
        }

        // If downloading a directory, avoid stat() on directory inode which reports ~128 bytes
        var isLocalDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isLocalDir)
        let isDirectoryDownload = isPull && (isLocalDir.boolValue || localURL.pathExtension.isEmpty)

        let fileMonitorTimer: DispatchSourceTimer?
        if isPull && !isDirectoryDownload {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + .milliseconds(60), repeating: .milliseconds(60))
            timer.setEventHandler {
                let path = localURL.path
                var st = stat()
                if stat(path, &st) == 0 {
                    let currentSize = st.st_size
                    let update = transferLock.withLock { s -> (shouldReport: Bool, pct: Double?, total: Int64) in
                        guard currentSize > s.lastReportedBytes else { return (false, nil, 0) }
                        s.lastReportedBytes = currentSize
                        let rawPct = s.knownTotalBytes > 0 ? (Double(currentSize) / Double(s.knownTotalBytes)) * 100.0 : 0.0
                        let pct = s.knownTotalBytes > 0 ? min(100.0, max(s.lastReportedPct, rawPct)) : nil
                        if let p = pct { s.lastReportedPct = max(s.lastReportedPct, p) }
                        return (true, pct, s.knownTotalBytes)
                    }

                    if update.shouldReport {
                        let (speed, eta) = computeSpeed(currentBytes: currentSize)
                        onProgress(FileTransferProgress(
                            percentage: update.pct,
                            transferredBytes: currentSize,
                            totalBytes: update.total,
                            speedBytesPerSec: speed,
                            etaSeconds: eta
                        ))
                    }
                }
            }
            timer.resume()
            fileMonitorTimer = timer
        } else {
            fileMonitorTimer = nil
        }

        defer {
            fileMonitorTimer?.cancel()
        }

        let progressRegex = try NSRegularExpression(
            pattern: "\\[\\s*(\\d+)%\\](?:\\s+([^:\\r\\n]+?)(?::\\s*(\\d+)%)?)?",
            options: []
        )
        let summaryRegex = try NSRegularExpression(
            pattern: "\\b([0-9]+(?:\\.[0-9]+)?)\\s*([KMGT]?B/s)\\s*\\(\\s*(\\d+)\\s+bytes\\s+in\\s+([0-9]+(?:\\.[0-9]+)?)s\\)",
            options: [.caseInsensitive]
        )

        var lineBuffer = ""
        var errorLines: [String] = []
        var readBuf = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(master, &readBuf, readBuf.count)
            if bytesRead <= 0 { break }

            guard let chunkStr = String(bytes: readBuf[0..<bytesRead], encoding: .utf8) else { continue }
            lineBuffer += chunkStr

            let parts = lineBuffer.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            if parts.count > 1 {
                for line in parts.dropLast() {
                    let clean = line
                        .replacingOccurrences(of: "\u{001B}[K", with: "")
                        .replacingOccurrences(of: "\u{001B}[?25l", with: "")
                        .replacingOccurrences(of: "\u{001B}[?25h", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if clean.isEmpty { continue }

                    let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)

                    if let match = progressRegex.firstMatch(in: clean, options: [], range: range) {
                        let pctStr = (clean as NSString).substring(with: match.range(at: 1))
                        let rawPct = Double(pctStr) ?? 0.0

                        var currentSubfile: String? = nil
                        if match.range(at: 2).location != NSNotFound {
                            let rawSub = (clean as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                            currentSubfile = URL(fileURLWithPath: rawSub).lastPathComponent
                        }

                        let update = transferLock.withLock { s -> (currentTransferred: Int64, effectivePct: Double, total: Int64) in
                            let transferredFromPct = (s.knownTotalBytes > 0) ? Int64((Double(s.knownTotalBytes) * (rawPct / 100.0)).rounded()) : 0
                            let currentTransferred = max(s.lastReportedBytes, transferredFromPct)
                            s.lastReportedBytes = currentTransferred

                            let computedPct = (s.knownTotalBytes > 0) ? min(100.0, (Double(currentTransferred) / Double(s.knownTotalBytes)) * 100.0) : rawPct
                            let effectivePct = min(100.0, max(s.lastReportedPct, max(rawPct, computedPct)))
                            s.lastReportedPct = effectivePct
                            return (currentTransferred, effectivePct, s.knownTotalBytes)
                        }

                        let (speed, eta) = computeSpeed(currentBytes: update.currentTransferred)

                        onProgress(FileTransferProgress(
                            percentage: update.effectivePct,
                            transferredBytes: update.currentTransferred,
                            totalBytes: update.total,
                            speedBytesPerSec: speed,
                            currentSubfile: currentSubfile,
                            etaSeconds: eta
                        ))
                    } else if let match = summaryRegex.firstMatch(in: clean, options: [], range: range) {
                        let speedValStr = (clean as NSString).substring(with: match.range(at: 1))
                        let speedUnit = (clean as NSString).substring(with: match.range(at: 2)).uppercased()
                        let bytesValStr = (clean as NSString).substring(with: match.range(at: 3))

                        var mult: Double = 1.0
                        if speedUnit.hasPrefix("K") { mult = 1024 }
                        else if speedUnit.hasPrefix("M") { mult = 1024 * 1024 }
                        else if speedUnit.hasPrefix("G") { mult = 1024 * 1024 * 1024 }

                        let parsedSpeed = (Double(speedValStr) ?? 0) * mult
                        let parsedBytes = Int64(bytesValStr) ?? 0

                        transferLock.withLock { s in
                            s.finalSpeed = parsedSpeed
                            s.finalBytes = parsedBytes
                            if s.knownTotalBytes == 0 {
                                s.knownTotalBytes = parsedBytes
                            }
                        }
                    } else if clean.lowercased().contains("error") || clean.lowercased().contains("failed") || clean.lowercased().contains("cannot") {
                        errorLines.append(clean)
                    }
                }
                lineBuffer = parts.last ?? ""
            }
        }

        proc.waitUntilExit()

        fileMonitorTimer?.cancel()

        if Task.isCancelled || activeProcessHolder.wasCancelled || proc.terminationStatus == 15 {
            throw CancellationError()
        }

        if proc.terminationStatus != 0 {
            let errDetail = errorLines.joined(separator: "\n")
            let msg = errDetail.isEmpty ? "Transfer failed with code \(proc.terminationStatus)" : errDetail
            throw NSError(
                domain: "ADBManager",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        let summary = transferLock.withLock { s -> (total: Int64, speed: Double) in
            let total = s.knownTotalBytes > 0 ? s.knownTotalBytes : s.finalBytes
            let speed = s.finalSpeed > 0 ? s.finalSpeed : (Double(total) / max(0.1, Date().timeIntervalSince(startTime)))
            return (total, speed)
        }

        onProgress(FileTransferProgress(
            percentage: 100.0,
            transferredBytes: summary.total,
            totalBytes: summary.total,
            speedBytesPerSec: summary.speed,
            currentSubfile: nil,
            etaSeconds: 0
        ))
    }

    private func runTransferFallback(
        adb: String,
        arguments: [String],
        direction: TransferDirection,
        localURL: URL,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (FileTransferProgress) -> Void
    ) async throws {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errPipe

        activeProcessHolder.set(process)

        defer {
            activeProcessHolder.set(nil)
        }

        let startTime = Date()
        let isPull = (direction == .download)
        var lastBytes: Int64 = 0

        let fileTimer: DispatchSourceTimer?
        if isPull {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + .milliseconds(80), repeating: .milliseconds(80))
            timer.setEventHandler {
                var st = stat()
                if stat(localURL.path, &st) == 0 {
                    let current = st.st_size
                    if current > lastBytes {
                        lastBytes = current
                        let elapsed = max(0.05, Date().timeIntervalSince(startTime))
                        let speed = Double(current) / elapsed
                        let eta = (totalBytes > current && speed > 0) ? Double(totalBytes - current) / speed : nil
                        let pct = totalBytes > 0 ? min(100.0, (Double(current) / Double(totalBytes)) * 100.0) : nil
                        onProgress(FileTransferProgress(
                            percentage: pct,
                            transferredBytes: current,
                            totalBytes: totalBytes,
                            speedBytesPerSec: speed,
                            etaSeconds: eta
                        ))
                    }
                }
            }
            timer.resume()
            fileTimer = timer
        } else {
            fileTimer = nil
        }

        defer {
            fileTimer?.cancel()
        }

        let outTask = Task.detached {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }
        let errTask = Task.detached {
            errPipe.fileHandleForReading.readDataToEndOfFile()
        }

        try process.run()
        process.waitUntilExit()

        _ = await outTask.value
        let errData = await errTask.value

        fileTimer?.cancel()

        if Task.isCancelled || activeProcessHolder.wasCancelled || process.terminationStatus == 15 {
            throw CancellationError()
        }

        if process.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(
                domain: "ADBManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errMsg.isEmpty ? "Transfer failed" : errMsg]
            )
        }

        let elapsed = max(0.1, Date().timeIntervalSince(startTime))
        let finalSpeed = Double(totalBytes) / elapsed
        onProgress(FileTransferProgress(
            percentage: 100.0,
            transferredBytes: totalBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: finalSpeed,
            etaSeconds: 0
        ))
    }

    /// Delete file or directory on device
    public func delete(serial: String, remotePath: String) async throws {
        let quoted = "'\(remotePath.replacingOccurrences(of: "'", with: "'\\''"))'"
        _ = try await executeAdb(["-s", serial, "shell", "rm", "-rf", quoted])
    }

    /// Delete multiple files or directories on device in batches
    public func deleteMultiple(serial: String, remotePaths: [String]) async throws {
        guard !remotePaths.isEmpty else { return }
        let chunkSize = 50
        for chunk in stride(from: 0, to: remotePaths.count, by: chunkSize) {
            let slice = Array(remotePaths[chunk..<min(chunk + chunkSize, remotePaths.count)])
            let quotedSlice = slice.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            var args = ["-s", serial, "shell", "rm", "-rf"]
            args.append(contentsOf: quotedSlice)
            _ = try await executeAdb(args)
        }
    }

    /// Create new folder
    public func createDirectory(serial: String, remotePath: String) async throws {
        let quoted = "'\(remotePath.replacingOccurrences(of: "'", with: "'\\''"))'"
        _ = try await executeAdb(["-s", serial, "shell", "mkdir", "-p", quoted])
    }

    /// Rename or move file / directory on device
    public func renamePath(serial: String, oldPath: String, newName: String) async throws {
        let parent = (oldPath as NSString).deletingLastPathComponent
        let cleanNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNewName.isEmpty, !cleanNewName.contains("/") else {
            throw NSError(domain: "ADBManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid file name."])
        }
        let newPath = parent == "/" ? "/\(cleanNewName)" : "\(parent)/\(cleanNewName)"
        let quotedOld = "'\(oldPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        let quotedNew = "'\(newPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        let res = try await executeAdbDetailed(["-s", serial, "shell", "mv", quotedOld, quotedNew])
        if res.exitCode != 0 {
            throw NSError(domain: "ADBManager", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.combinedOutput])
        }
    }

    /// Deep search across Android storage
    public func searchFiles(serial: String, basePath: String, query: String, maxResults: Int = 80) async throws -> [DeviceFile] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }
        let target = basePath.isEmpty ? "/sdcard" : basePath
        let quotedTarget = "'\(target.replacingOccurrences(of: "'", with: "'\\''"))'"
        let safeQuery = cleanQuery.replacingOccurrences(of: "'", with: "")

        let script = """
        find \(quotedTarget) -maxdepth 5 -iname '*\(safeQuery)*' 2>/dev/null | head -n \(maxResults) | while IFS= read -r f; do
            [ -e "$f" ] && ls -ld "$f" 2>/dev/null
        done
        """
        let raw = try await executeAdb(["-s", serial, "shell", "sh", "-c", script])
        var results: [DeviceFile] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 6 else { continue }

            let permissions = tokens[0]
            let isDir = permissions.hasPrefix("d")
            var sizeBytes: Int64 = 0
            if !isDir && tokens.count >= 5 {
                sizeBytes = Int64(tokens[4]) ?? 0
            }

            var filePath = ""
            if let pathIndex = tokens.enumerated().first(where: { $0.offset >= 5 && $0.element.hasPrefix("/") })?.offset {
                filePath = tokens.dropFirst(pathIndex).joined(separator: " ")
            } else if tokens.count >= 7 {
                filePath = tokens.dropFirst(6).joined(separator: " ")
            }

            if !filePath.isEmpty {
                let name = (filePath as NSString).lastPathComponent
                results.append(DeviceFile(
                    name: name,
                    path: filePath,
                    isDirectory: isDir,
                    sizeBytes: sizeBytes,
                    modifiedDate: nil,
                    permissions: permissions
                ))
            }
        }
        return results
    }

    /// Scan and fetch media files (photos, videos) from device storage
    public func fetchMediaFiles(serial: String, source: MediaSource) async throws -> [PhotoItem] {
        let searchRoots = source.searchPaths
        var combinedScript = ""
        for path in searchRoots {
            let quoted = "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
            combinedScript += """
            if [ -d \(quoted) ]; then
                find \(quoted) -maxdepth 3 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.heic" -o -iname "*.mp4" -o -iname "*.mov" \\) 2>/dev/null | head -n 300 | while IFS= read -r f; do
                    [ -f "$f" ] && stat -c "%s %Y %n" "$f" 2>/dev/null || ls -ld "$f" 2>/dev/null
                done
            fi
            """
        }
        let raw = try await executeAdb(["-s", serial, "shell", "sh", "-c", combinedScript])
        var items: [PhotoItem] = []
        var seenPaths = Set<String>()

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 3 else { continue }

            var size: Int64 = 0
            var timestamp: TimeInterval = 0
            var path = ""

            // stat format: "%s %Y %n"
            if let parsedSize = Int64(tokens[0]), let parsedTime = TimeInterval(tokens[1]) {
                size = parsedSize
                timestamp = parsedTime
                path = tokens.dropFirst(2).joined(separator: " ")
            } else if tokens.count >= 6 {
                // Fallback to ls -ld format
                size = Int64(tokens[4]) ?? 0
                if let pIdx = tokens.enumerated().first(where: { $0.offset >= 5 && $0.element.hasPrefix("/") })?.offset {
                    path = tokens.dropFirst(pIdx).joined(separator: " ")
                }
            }

            guard !path.isEmpty, !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)

            let filename = (path as NSString).lastPathComponent
            let ext = (path as NSString).pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "mkv", "3gp"].contains(ext)
            let date = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()

            items.append(PhotoItem(
                name: filename,
                path: path,
                sizeBytes: size,
                dateModified: date,
                isVideo: isVideo
            ))
        }

        return items.sorted { $0.dateModified > $1.dateModified }
    }

    /// Parse known Android Package Manager installation errors into user-friendly guidance
    public static func parseInstallFailure(output: String) -> String {
        let regex = try? NSRegularExpression(pattern: "Failure\\s*\\[([A-Z_0-9]+)(?::\\s*([^\\]]+))?\\]", options: [.caseInsensitive])
        if let match = regex?.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)) {
            let code = (output as NSString).substring(with: match.range(at: 1))
            let detail = match.range(at: 2).location != NSNotFound ? (output as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces) : ""
            switch code {
            case "INSTALL_FAILED_UPDATE_INCOMPATIBLE":
                return "Signature mismatch: Existing app signatures do not match the new APK. Please uninstall the previous version from your device first."
            case "INSTALL_FAILED_VERSION_DOWNGRADE":
                return "Version downgrade rejected: A newer version of this app is already installed on the phone."
            case "INSTALL_FAILED_INSUFFICIENT_STORAGE":
                return "Insufficient storage: Free up disk space on the phone to install this APK."
            case "INSTALL_FAILED_NO_MATCHING_ABIS":
                return "Architecture mismatch: This APK is not compatible with your device's CPU architecture."
            case "INSTALL_FAILED_USER_RESTRICTED":
                return "Installation blocked: Please enable 'Install via USB' in Android Developer Options on your phone."
            case "INSTALL_FAILED_TEST_ONLY":
                return "Test-only build: This APK requires test package installation permissions."
            case "INSTALL_FAILED_DEPRECATED_SDK_VERSION":
                return "Deprecated target SDK: This app is too old for Android 14+."
            case "INSTALL_FAILED_ALREADY_EXISTS":
                return "Package already exists on device."
            default:
                return !detail.isEmpty ? "\(code): \(detail)" : code
            }
        }
        if !output.isEmpty {
            return output
        }
        return "Installation failed (unknown error)"
    }

    /// Install APK with flags -r (reinstall), -d (downgrade), -t (test-only), -g (grant permissions)
    public func installApk(serial: String, apkURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: apkURL.path) else {
            throw NSError(
                domain: "ADBManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "APK file not found at: \(apkURL.lastPathComponent)"]
            )
        }

        let res = try await executeAdbDetailed(["-s", serial, "install", "-r", "-d", "-t", "-g", apkURL.path])
        let output = res.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.contains("Failure [") || res.exitCode != 0 {
            let reason = Self.parseInstallFailure(output: output)
            throw NSError(
                domain: "ADBManager",
                code: Int(res.exitCode != 0 ? res.exitCode : 1),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }

        return output.isEmpty ? "Success" : output
    }

    /// Install APK located directly on device storage
    public func installApkOnDevice(serial: String, remotePath: String) async throws -> String {
        let quoted = "'\(remotePath.replacingOccurrences(of: "'", with: "'\\''"))'"
        let res = try await executeAdbDetailed(["-s", serial, "shell", "pm", "install", "-r", "-d", "-t", "-g", quoted])
        let output = res.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.contains("Failure [") || res.exitCode != 0 {
            let reason = Self.parseInstallFailure(output: output)
            throw NSError(
                domain: "ADBManager",
                code: Int(res.exitCode != 0 ? res.exitCode : 1),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }

        return output.isEmpty ? "Success" : output
    }

    /// List 3rd party installed apps (legacy convenience)
    public func listInstalledPackages(serial: String) async throws -> [String] {
        let output = try await executeAdb(["-s", serial, "shell", "pm", "list", "packages", "-3"])
        return output.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Production App Manager: Fetch rich application list with filters
    public func listApps(serial: String, filter: AppFilterType) async throws -> [AppInfo] {
        var args = ["-s", serial, "shell", "pm", "list", "packages", "-f"]
        switch filter {
        case .thirdParty:
            args.append("-3")
        case .system:
            args.append("-s")
        case .disabled:
            args.append("-d")
        case .all:
            break
        }

        async let rawList = executeAdb(args)
        async let disabledRaw = executeAdb(["-s", serial, "shell", "pm", "list", "packages", "-d"])

        let output = (try? await rawList) ?? ""
        let disabledOutput = (try? await disabledRaw) ?? ""

        var disabledSet = Set<String>()
        for dLine in disabledOutput.components(separatedBy: .newlines) {
            let clean = dLine.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty {
                disabledSet.insert(clean)
            }
        }

        var apps: [AppInfo] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("package:") else { continue }
            let content = String(trimmed.dropFirst("package:".count))

            // Format: /data/app/~~.../base.apk=com.example.app
            guard let eqIdx = content.lastIndex(of: "=") else { continue }
            let apkPath = String(content[..<eqIdx])
            let pkg = String(content[content.index(after: eqIdx)...])

            let isSystem = apkPath.hasPrefix("/system") || apkPath.hasPrefix("/product") || apkPath.hasPrefix("/vendor") || apkPath.hasPrefix("/apex")
            let isEnabled = !disabledSet.contains(pkg)

            apps.append(AppInfo(
                packageName: pkg,
                apkPath: apkPath,
                isSystemApp: isSystem,
                isEnabled: isEnabled
            ))
        }

        return apps.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// Launch app on phone screen
    @discardableResult
    public func launchApp(serial: String, packageName: String) async throws -> String {
        return try await executeAdb(["-s", serial, "shell", "monkey", "-p", packageName, "-c", "android.intent.category.LAUNCHER", "1"])
    }

    /// Force stop application
    public func forceStopApp(serial: String, packageName: String) async throws {
        _ = try await executeAdb(["-s", serial, "shell", "am", "force-stop", packageName])
    }

    /// Clear application data / cache
    @discardableResult
    public func clearAppData(serial: String, packageName: String) async throws -> String {
        return try await executeAdb(["-s", serial, "shell", "pm", "clear", packageName])
    }

    /// Enable or disable app (freeze/unfreeze)
    @discardableResult
    public func setAppEnabled(serial: String, packageName: String, enable: Bool) async throws -> String {
        if enable {
            return try await executeAdb(["-s", serial, "shell", "pm", "enable", packageName])
        } else {
            return try await executeAdb(["-s", serial, "shell", "pm", "disable-user", "--user", "0", packageName])
        }
    }

    /// Fetch detailed package metadata via dumpsys
    public func fetchAppDetails(serial: String, packageName: String) async -> AppDetailedInfo {
        var details = AppDetailedInfo(packageName: packageName)
        guard let output = try? await executeAdb(["-s", serial, "shell", "dumpsys", "package", packageName]) else {
            return details
        }

        var isCollectingPermissions = false
        var permissions: [String] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("versionName=") {
                details.versionName = trimmed.replacingOccurrences(of: "versionName=", with: "")
            } else if trimmed.hasPrefix("versionCode=") {
                let parts = trimmed.components(separatedBy: " ")
                details.versionCode = parts.first?.replacingOccurrences(of: "versionCode=", with: "") ?? ""
                for part in parts {
                    if part.hasPrefix("targetSdk=") {
                        details.targetSdk = part.replacingOccurrences(of: "targetSdk=", with: "")
                    } else if part.hasPrefix("minSdk=") {
                        details.minSdk = part.replacingOccurrences(of: "minSdk=", with: "")
                    }
                }
            } else if trimmed.hasPrefix("firstInstallTime=") {
                details.firstInstallTime = trimmed.replacingOccurrences(of: "firstInstallTime=", with: "")
            } else if trimmed.hasPrefix("lastUpdateTime=") {
                details.lastUpdateTime = trimmed.replacingOccurrences(of: "lastUpdateTime=", with: "")
            } else if trimmed.hasPrefix("codePath=") {
                details.apkPath = trimmed.replacingOccurrences(of: "codePath=", with: "")
            } else if trimmed.hasPrefix("requested permissions:") {
                isCollectingPermissions = true
            } else if isCollectingPermissions {
                if trimmed.hasPrefix("android.permission.") {
                    let permName = trimmed.replacingOccurrences(of: "android.permission.", with: "")
                    if !permissions.contains(permName) {
                        permissions.append(permName)
                    }
                } else if !trimmed.isEmpty && !trimmed.contains("permission") {
                    isCollectingPermissions = false
                }
            }
        }

        details.permissions = permissions.sorted()
        return details
    }

    // MARK: - Production Storage Lens Scanners

    /// Scans directory breakdown with percentage calculation (folders only)
    public func scanDirectoryBreakdown(serial: String, path: String) async throws -> [StorageFolderItem] {
        let cleanPath = path.isEmpty ? "/sdcard" : path
        let quoted = "'\(cleanPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        // Resolve symlink so toybox du properly scans internal storage and filter directories only
        let script = """
        target=\(quoted)
        if [ -L "$target" ]; then
            resolved="$(readlink -f "$target" 2>/dev/null)"
            [ -n "$resolved" ] && target="$resolved"
        fi
        for item in "$target"/* "$target"/.[!.]*; do
            if [ -d "$item" ]; then
                du -sk "$item" 2>/dev/null
            fi
        done
        """
        let raw = try await executeAdb(["-s", serial, "shell", "sh", "-c", script])
        var list: [StorageFolderItem] = []

        let lines = raw.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, let kb = Int64(parts[0]) else { continue }
            let itemPath = parts.dropFirst().joined(separator: " ")
            let name = (itemPath as NSString).lastPathComponent

            if name.isEmpty || name == "." || name == ".." {
                continue
            }
            list.append(StorageFolderItem(name: name, path: itemPath, sizeBytes: kb * 1024))
        }

        let totalBytes = list.reduce(0) { $0 + $1.sizeBytes }
        for i in list.indices {
            if totalBytes > 0 {
                list[i].percentageOfParent = Double(list[i].sizeBytes) / Double(totalBytes)
            }
        }

        return list.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Scans largest files on device (> minMB threshold) up to depth 7
    public func scanLargeFiles(serial: String, path: String, minMB: Int) async throws -> [StorageLargeFile] {
        let cleanPath = path.isEmpty ? "/sdcard" : path
        let quoted = "'\(cleanPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        let script = """
        target=\(quoted)
        if [ -L "$target" ]; then
            resolved="$(readlink -f "$target" 2>/dev/null)"
            [ -n "$resolved" ] && target="$resolved"
        fi
        find "$target" -maxdepth 7 -type f -size +\(minMB)M 2>/dev/null | while IFS= read -r f; do
            [ -n "$f" ] && ls -ld "$f" 2>/dev/null
        done
        """
        let raw = try await executeAdb(["-s", serial, "shell", "sh", "-c", script])
        var files: [StorageLargeFile] = []
        let lines = raw.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 6 else { continue }

            var size: Int64 = 0
            var filePath = ""

            // tokens[4] is the size in bytes in ls -ld output
            if tokens.count >= 5 {
                size = Int64(tokens[4]) ?? 0
            }

            // Find where the file path starts (first token with index >= 5 starting with /)
            if let pathIndex = tokens.enumerated().first(where: { $0.offset >= 5 && $0.element.hasPrefix("/") })?.offset {
                filePath = tokens.dropFirst(pathIndex).joined(separator: " ")
            } else if tokens.count >= 7 {
                filePath = tokens.dropFirst(6).joined(separator: " ")
            }

            if !filePath.isEmpty && size > 0 {
                let name = (filePath as NSString).lastPathComponent
                files.append(StorageLargeFile(name: name, path: filePath, sizeBytes: size))
            }
        }
        return files.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Pair via Wi-Fi ADB (Android 11+)
    public func pairWireless(host: String, port: Int, code: String) async throws -> String {
        return try await executeAdb(["pair", "\(host):\(port)", code])
    }

    /// Connect via Wi-Fi ADB
    public func connectWireless(host: String, port: Int) async throws -> String {
        return try await executeAdb(["connect", "\(host):\(port)"])
    }

    // MARK: - Device Screenshots & Tools

    /// Captures a full-resolution screenshot from the connected device
    public func takeScreenshot(serial: String) async throws -> NSImage {
        // Fast path: exec-out screencap -p streams raw PNG bytes to stdout
        do {
            let data = try await executeAdbBinary(["-s", serial, "exec-out", "screencap", "-p"])
            if data.count > 8,
               data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47,
               let image = NSImage(data: data) {
                return image
            }
        } catch {
            // exec-out may not be supported or failed; fall back to file transfer
        }

        // Fallback: save to device storage, pull to temp local file, and load
        let remotePath = "/sdcard/.droidsync_screencap_\(Int(Date().timeIntervalSince1970)).png"
        _ = try await executeAdb(["-s", serial, "shell", "screencap", "-p", remotePath])

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("screencap_\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            Task { [weak self] in
                _ = try? await self?.executeAdb(["-s", serial, "shell", "rm", "-f", remotePath])
            }
        }

        try await pullFile(serial: serial, remotePath: remotePath, localURL: tempURL)
        guard let data = try? Data(contentsOf: tempURL), let image = NSImage(data: data) else {
            throw NSError(domain: "ADBManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode screenshot image from device."])
        }
        return image
    }

    // MARK: - Power & Device Controls

    public enum RebootMode: String, CaseIterable, Identifiable, Sendable {
        case normal = "Reboot System"
        case recovery = "Recovery Mode"
        case bootloader = "Bootloader / Fastboot"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .normal: return "arrow.clockwise"
            case .recovery: return "wrench.and.screwdriver"
            case .bootloader: return "terminal"
            }
        }
    }

    /// Reboots the connected Android device
    @discardableResult
    public func rebootDevice(serial: String, mode: RebootMode) async throws -> String {
        switch mode {
        case .normal:
            return try await executeAdb(["-s", serial, "reboot"])
        case .recovery:
            return try await executeAdb(["-s", serial, "reboot", "recovery"])
        case .bootloader:
            return try await executeAdb(["-s", serial, "reboot", "bootloader"])
        }
    }

    /// Sends a hardware keyevent to the device
    public func sendKeyEvent(serial: String, keyCode: Int) async throws {
        _ = try await executeAdb(["-s", serial, "shell", "input", "keyevent", "\(keyCode)"])
    }

    /// Toggles screen lock/wake (KEYCODE_POWER = 26)
    public func toggleScreenLock(serial: String) async throws {
        try await sendKeyEvent(serial: serial, keyCode: 26)
    }

    public enum VolumeAction: Sendable {
        case up, down, mute
    }

    /// Adjusts device volume
    public func changeVolume(serial: String, action: VolumeAction) async throws {
        switch action {
        case .up:
            try await sendKeyEvent(serial: serial, keyCode: 24) // KEYCODE_VOLUME_UP
        case .down:
            try await sendKeyEvent(serial: serial, keyCode: 25) // KEYCODE_VOLUME_DOWN
        case .mute:
            try await sendKeyEvent(serial: serial, keyCode: 164) // KEYCODE_VOLUME_MUTE
        }
    }

    // MARK: - Clipboard & Text Input

    /// Sends text directly into active input on the Android device
    public func sendTextToDevice(serial: String, text: String) async throws {
        guard !text.isEmpty else { return }
        var escaped = ""
        for char in text {
            if char == " " {
                escaped.append("%s")
            } else if char == "\n" {
                if !escaped.isEmpty {
                    _ = try await executeAdb(["-s", serial, "shell", "input", "text", escaped])
                    escaped = ""
                }
                _ = try await executeAdb(["-s", serial, "shell", "input", "keyevent", "66"])
            } else if "\\\"'$`&|;()<>\t*?#~=[]{}".contains(char) {
                escaped.append("\\\(char)")
            } else {
                escaped.append(char)
            }
        }
        if !escaped.isEmpty {
            _ = try await executeAdb(["-s", serial, "shell", "input", "text", escaped])
        }
    }

    // MARK: - Screen Recording

    public final class ScreenRecordingSession: @unchecked Sendable {
        public let serial: String
        public let remotePath: String
        fileprivate let process: Process
        fileprivate let startTime: Date

        fileprivate init(serial: String, remotePath: String, process: Process) {
            self.serial = serial
            self.remotePath = remotePath
            self.process = process
            self.startTime = Date()
        }

        public var durationSeconds: Int {
            Int(Date().timeIntervalSince(startTime))
        }

        public var isRunning: Bool {
            process.isRunning
        }
    }

    /// Starts recording the device screen asynchronously
    public func startScreenRecording(serial: String) async throws -> ScreenRecordingSession {
        guard let adb = resolveAdbPath() else {
            throw NSError(domain: "ADBManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "ADB executable not found."])
        }
        let remotePath = "/sdcard/droidsync_record_\(Int(Date().timeIntervalSince1970)).mp4"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["-s", serial, "shell", "screenrecord", "--time-limit", "180", remotePath]

        try process.run()
        return ScreenRecordingSession(serial: serial, remotePath: remotePath, process: process)
    }

    /// Stops recording the screen, pulls the video file to destinationURL, and deletes remote file
    public func stopScreenRecording(session: ScreenRecordingSession, destinationURL: URL) async throws {
        if session.process.isRunning {
            kill(session.process.processIdentifier, SIGINT)
            for _ in 0..<30 {
                if !session.process.isRunning { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if session.process.isRunning {
                session.process.terminate()
            }
        }

        try await pullFile(serial: session.serial, remotePath: session.remotePath, localURL: destinationURL)
        _ = try? await executeAdb(["-s", session.serial, "shell", "rm", "-f", session.remotePath])
    }

    // MARK: - APK Helpers

    /// Resolves full device path of an installed package
    public func resolvePackageApkPath(serial: String, packageName: String) async throws -> String {
        let output = try await executeAdb(["-s", serial, "shell", "pm", "path", packageName])
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("package:") {
                return String(trimmed.dropFirst("package:".count))
            }
        }
        throw NSError(domain: "ADBManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not locate APK path for \(packageName)"])
    }

    // MARK: - Screen Mirroring (scrcpy)

    /// Discovers scrcpy binary on macOS
    public func resolveScrcpyPath() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "/opt/local/bin/scrcpy",
            "/usr/bin/scrcpy"
        ]
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let shellCheck = runProcess(executable: "/usr/bin/which", arguments: ["scrcpy"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !shellCheck.isEmpty && FileManager.default.isExecutableFile(atPath: shellCheck) {
            return shellCheck
        }
        return nil
    }

    public var isScrcpyAvailable: Bool {
        resolveScrcpyPath() != nil
    }

    /// Launch Screen Mirroring via scrcpy
    @discardableResult
    public func launchScreenMirror(serial: String, title: String? = nil) async throws -> Process {
        guard let scrcpy = resolveScrcpyPath() else {
            throw NSError(
                domain: "ADBManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "scrcpy not found. Install it easily with Homebrew: brew install scrcpy"]
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpy)
        var args = ["-s", serial, "--stay-awake"]
        let windowTitle = title ?? "DroidSync — Screen Mirror"
        args.append(contentsOf: ["--window-title", windowTitle])
        process.arguments = args
        try process.run()
        return process
    }
}
