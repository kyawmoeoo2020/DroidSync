import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct DashboardView: View {
    @ObservedObject var appState: AppState

    // Tools & Action States
    @State private var capturedScreenshot: NSImage?
    @State private var isCapturingScreenshot = false
    @State private var showClipboardSheet = false
    @State private var showScrcpyInstallSheet = false
    @State private var toolStatusMessage = ""
    @State private var toolStatusIsError = false

    // Screen Recording
    @State private var isRecordingScreen = false
    @State private var recordingSession: ADBManager.ScreenRecordingSession?
    @State private var recordingDuration = 0
    @State private var recordingTimer: Timer?

    // Reboot Confirmation
    @State private var showRebootAlert = false
    @State private var pendingRebootMode: ADBManager.RebootMode = .normal

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let device = appState.selectedDevice {
                    // Header Card
                    HStack(alignment: .center, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Image(systemName: "iphone.gen3")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(device.name)
                                .font(.title)
                                .fontWeight(.bold)

                            HStack(spacing: 8) {
                                Label(device.osVersion, systemImage: "gearshape.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .foregroundColor(.secondary)

                                Label(device.connectionType.rawValue, systemImage: device.connectionType == .wifi ? "wifi" : "cable.connector")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .foregroundColor(.secondary)

                                Text("ID: \(device.id)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(action: {
                            appState.refreshDevices()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        // Storage Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Storage", systemImage: "internaldrive.fill")
                                    .font(.headline)
                                Spacer()
                                Text("\(device.storage.formattedUsed) / \(device.storage.formattedTotal)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            // Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 12)

                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(device.storage.usedPercentage), height: 12)
                                }
                            }
                            .frame(height: 12)

                            HStack {
                                Text("\(device.storage.formattedFree) Available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f%% Used", device.storage.usedPercentage * 100))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)

                        // Battery Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Battery Health", systemImage: "battery.100")
                                    .font(.headline)
                                Spacer()
                                Text("\(device.batteryLevel)%")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(device.batteryLevel > 20 ? .green : .red)
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Status")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        if device.isCharging {
                                             Image(systemName: "bolt.fill")
                                                .foregroundColor(.green)
                                            Text("Charging")
                                        } else {
                                            Text("On Battery")
                                        }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Temperature")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f°C", device.batteryTempCelsius))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }

                    // Status Message Banner
                    if !toolStatusMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: toolStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(toolStatusIsError ? .red : .green)
                            Text(toolStatusMessage)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Dismiss") {
                                toolStatusMessage = ""
                            }
                            .buttonStyle(PlainButtonStyle())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(toolStatusIsError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                        .cornerRadius(8)
                    }

                    // Device Tools & Quick Controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Device Tools & Utilities")
                            .font(.headline)

                        HStack(spacing: 12) {
                            // Screen Mirror Button
                            QuickActionButton(
                                title: "Screen Mirror",
                                subtitle: "Live Display & Mouse",
                                icon: "macbook.and.iphone",
                                color: .purple
                            ) {
                                triggerScreenMirror(serial: device.id)
                            }

                            // Screenshot Button
                            QuickActionButton(
                                title: isCapturingScreenshot ? "Capturing..." : "Screenshot",
                                subtitle: "Mac Preview & Copy",
                                icon: "camera.viewfinder",
                                color: .indigo
                            ) {
                                captureScreenshot(serial: device.id)
                            }
                            .disabled(isCapturingScreenshot)

                            // Screen Record Button
                            QuickActionButton(
                                title: isRecordingScreen ? "Stop (\(formatSeconds(recordingDuration)))" : "Record Screen",
                                subtitle: isRecordingScreen ? "Recording active..." : "Capture Phone MP4",
                                icon: isRecordingScreen ? "stop.circle.fill" : "record.circle",
                                color: isRecordingScreen ? .red : .pink
                            ) {
                                toggleScreenRecording(serial: device.id)
                            }

                            // Send Mac Clipboard to Phone
                            QuickActionButton(
                                title: "Send to Phone",
                                subtitle: "Push Mac Clipboard",
                                icon: "doc.on.clipboard.fill",
                                color: .teal
                            ) {
                                showClipboardSheet = true
                            }

                            // Power & Hardware Controls Card
                            Menu {
                                Section("Power Menu") {
                                    Button {
                                        promptReboot(mode: .normal)
                                    } label: {
                                        Label("Reboot System", systemImage: "arrow.clockwise")
                                    }

                                    Button {
                                        promptReboot(mode: .recovery)
                                    } label: {
                                        Label("Reboot to Recovery Mode", systemImage: "wrench.and.screwdriver")
                                    }

                                    Button {
                                        promptReboot(mode: .bootloader)
                                    } label: {
                                        Label("Reboot to Bootloader / Fastboot", systemImage: "terminal")
                                    }
                                }

                                Section("Device Controls") {
                                    Button {
                                        toggleLock(serial: device.id)
                                    } label: {
                                        Label("Lock / Wake Screen", systemImage: "lock.fill")
                                    }

                                    Button {
                                        adjustVolume(serial: device.id, action: .up)
                                    } label: {
                                        Label("Volume Up", systemImage: "speaker.wave.3.fill")
                                    }

                                    Button {
                                        adjustVolume(serial: device.id, action: .down)
                                    } label: {
                                        Label("Volume Down", systemImage: "speaker.wave.1.fill")
                                    }

                                    Button {
                                        adjustVolume(serial: device.id, action: .mute)
                                    } label: {
                                        Label("Mute Volume", systemImage: "speaker.slash.fill")
                                    }
                                }
                            } label: {
                                QuickActionCardContent(
                                    title: "Power & Controls",
                                    subtitle: "Reboot, Lock, Audio",
                                    icon: "power.circle.fill",
                                    color: .orange
                                )
                            }
                            .menuStyle(BorderlessButtonMenuStyle())
                        }
                    }

                    // Navigation Quick Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Navigation")
                            .font(.headline)

                        HStack(spacing: 12) {
                            QuickActionButton(
                                title: "Browse Files",
                                subtitle: "Explore /sdcard",
                                icon: "folder.fill",
                                color: .blue
                            ) {
                                appState.navigateTo(path: "/sdcard")
                            }

                            QuickActionButton(
                                title: "Photos & Media",
                                subtitle: "Gallery & Export",
                                icon: "photo.on.rectangle.angled",
                                color: .purple
                            ) {
                                appState.currentSection = .photos
                            }

                            QuickActionButton(
                                title: "App Manager",
                                subtitle: "Install & Backup APKs",
                                icon: "square.grid.2x2.fill",
                                color: .green
                            ) {
                                appState.currentSection = .apps
                                appState.loadPackages()
                            }

                            QuickActionButton(
                                title: "Wireless Mode",
                                subtitle: "Connect via Wi-Fi",
                                icon: "wifi",
                                color: .orange
                            ) {
                                appState.currentSection = .wirelessPair
                            }
                        }
                    }
                } else {
                    // No Device Selected State
                    VStack(spacing: 16) {
                        if let logo = dashboardLogo {
                            Image(nsImage: logo)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                        } else {
                            Image(systemName: "cable.connector.horizontal")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 4) {
                            Text("Welcome to DroidSync")
                                .font(.title)
                                .fontWeight(.bold)

                            Text("Developed by Kyaw Moe Oo")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text("Connect your Android phone using a USB cable and ensure **USB Debugging** is turned on in Developer Options.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 450)

                        Button(action: {
                            appState.refreshDevices()
                        }) {
                            Label("Scan for Devices", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 350)
                }
            }
            .padding(24)
        }
        // Screenshot Preview Sheet
        .sheet(isPresented: Binding(
            get: { capturedScreenshot != nil },
            set: { if !$0 { capturedScreenshot = nil } }
        )) {
            if let img = capturedScreenshot {
                ScreenshotPreviewSheet(
                    image: img,
                    onDismiss: { capturedScreenshot = nil },
                    onRetake: {
                        capturedScreenshot = nil
                        if let dev = appState.selectedDevice {
                            captureScreenshot(serial: dev.id)
                        }
                    }
                )
            }
        }
        // Clipboard Push Sheet
        .sheet(isPresented: $showClipboardSheet) {
            if let dev = appState.selectedDevice {
                SendClipboardSheet(serial: dev.id) {
                    showClipboardSheet = false
                }
            }
        }
        // Screen Mirror Helper Sheet
        .sheet(isPresented: $showScrcpyInstallSheet) {
            ScrcpyInstallSheet {
                showScrcpyInstallSheet = false
            }
        }
        // Reboot Confirmation Alert
        .alert(isPresented: $showRebootAlert) {
            Alert(
                title: Text("Restart Device?"),
                message: Text("Are you sure you want to trigger \(pendingRebootMode.rawValue) on \(appState.selectedDevice?.name ?? "your phone")?"),
                primaryButton: .destructive(Text("Restart")) {
                    executeReboot()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Actions

    private func triggerScreenMirror(serial: String) {
        if ADBManager.shared.isScrcpyAvailable {
            toolStatusMessage = "Launching Screen Mirror..."
            toolStatusIsError = false
            Task {
                do {
                    let title = "\(appState.selectedDevice?.name ?? "Android") — DroidSync Mirror"
                    try await ADBManager.shared.launchScreenMirror(serial: serial, title: title)
                    await MainActor.run {
                        self.toolStatusMessage = "Screen Mirror active"
                        self.toolStatusIsError = false
                    }
                } catch {
                    await MainActor.run {
                        self.toolStatusMessage = "Failed to launch mirror: \(error.localizedDescription)"
                        self.toolStatusIsError = true
                    }
                }
            }
        } else {
            showScrcpyInstallSheet = true
        }
    }

    private func captureScreenshot(serial: String) {
        isCapturingScreenshot = true
        toolStatusMessage = "Capturing phone screenshot..."
        toolStatusIsError = false

        Task {
            do {
                let img = try await ADBManager.shared.takeScreenshot(serial: serial)
                await MainActor.run {
                    self.isCapturingScreenshot = false
                    self.capturedScreenshot = img
                    self.toolStatusMessage = ""
                }
            } catch {
                await MainActor.run {
                    self.isCapturingScreenshot = false
                    self.toolStatusMessage = "Screenshot failed: \(error.localizedDescription)"
                    self.toolStatusIsError = true
                }
            }
        }
    }

    private func toggleScreenRecording(serial: String) {
        if isRecordingScreen {
            stopScreenRecording()
        } else {
            startScreenRecording(serial: serial)
        }
    }

    private func startScreenRecording(serial: String) {
        toolStatusMessage = "Starting screen recording..."
        toolStatusIsError = false

        Task {
            do {
                let session = try await ADBManager.shared.startScreenRecording(serial: serial)
                await MainActor.run {
                    self.recordingSession = session
                    self.isRecordingScreen = true
                    self.recordingDuration = 0
                    self.toolStatusMessage = "Recording device screen..."
                    self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        Task { @MainActor in
                            self.recordingDuration += 1
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.toolStatusMessage = "Recording error: \(error.localizedDescription)"
                    self.toolStatusIsError = true
                }
            }
        }
    }

    private func stopScreenRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecordingScreen = false

        guard let session = recordingSession else { return }
        toolStatusMessage = "Finalizing and saving screen recording..."
        toolStatusIsError = false

        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "DroidSync_Recording_\(formatter.string(from: Date())).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true

        var targetURL: URL?
        if panel.runModal() == .OK, let url = panel.url {
            targetURL = url
        } else {
            targetURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
                .appendingPathComponent("DroidSync_Recording_\(formatter.string(from: Date())).mp4")
        }

        guard let dest = targetURL else {
            toolStatusMessage = "Recording cancelled"
            return
        }

        Task {
            do {
                try await ADBManager.shared.stopScreenRecording(session: session, destinationURL: dest)
                await MainActor.run {
                    self.recordingSession = nil
                    self.toolStatusMessage = "Screen recording saved: \(dest.lastPathComponent)"
                    self.toolStatusIsError = false
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            } catch {
                await MainActor.run {
                    self.toolStatusMessage = "Failed to save recording: \(error.localizedDescription)"
                    self.toolStatusIsError = true
                }
            }
        }
    }

    private func promptReboot(mode: ADBManager.RebootMode) {
        pendingRebootMode = mode
        showRebootAlert = true
    }

    private func executeReboot() {
        guard let device = appState.selectedDevice else { return }
        let mode = pendingRebootMode
        toolStatusMessage = "Sending \(mode.rawValue) command..."
        toolStatusIsError = false

        Task {
            do {
                try await ADBManager.shared.rebootDevice(serial: device.id, mode: mode)
                await MainActor.run {
                    self.toolStatusMessage = "Device restarting (\(mode.rawValue))"
                    self.toolStatusIsError = false
                }
            } catch {
                await MainActor.run {
                    self.toolStatusMessage = "Reboot failed: \(error.localizedDescription)"
                    self.toolStatusIsError = true
                }
            }
        }
    }

    private func toggleLock(serial: String) {
        Task {
            do {
                try await ADBManager.shared.toggleScreenLock(serial: serial)
            } catch {
                await MainActor.run {
                    self.toolStatusMessage = "Screen toggle failed: \(error.localizedDescription)"
                    self.toolStatusIsError = true
                }
            }
        }
    }

    private func adjustVolume(serial: String, action: ADBManager.VolumeAction) {
        Task {
            do {
                try await ADBManager.shared.changeVolume(serial: serial, action: action)
            } catch {
                await MainActor.run {
                    self.toolStatusMessage = "Volume adjustment failed: \(error.localizedDescription)"
                    self.toolStatusIsError = true
                }
            }
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var dashboardLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                     Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "DroidSync_Logo", withExtension: "png") ??
                     Bundle.module.url(forResource: "DroidSync_Logo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }
}

// MARK: - Reusable Quick Action Views

private struct QuickActionCardContent: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionCardContent(title: title, subtitle: subtitle, icon: icon, color: color)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Screenshot Preview Sheet

private struct ScreenshotPreviewSheet: View {
    let image: NSImage
    let onDismiss: () -> Void
    let onRetake: () -> Void

    @State private var copiedToClipboard = false
    @State private var saveStatusMessage = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Device Screenshot")
                        .font(.headline)
                }

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ZStack {
                Color(NSColor.controlBackgroundColor)
                    .cornerRadius(10)

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: 420, maxHeight: 520)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)

            if copiedToClipboard {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Copied screenshot to Mac clipboard!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .transition(.opacity)
            } else if !saveStatusMessage.isEmpty {
                Text(saveStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onRetake) {
                    Label("Retake", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button(action: copyToClipboard) {
                    Label(copiedToClipboard ? "Copied!" : "Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: saveToFile) {
                    Label("Save Image...", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 600)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        withAnimation {
            copiedToClipboard = true
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        panel.nameFieldStringValue = "DroidSync_Screenshot_\(timestamp).png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
                saveStatusMessage = "Saved to \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

// MARK: - Send Clipboard Sheet

private struct SendClipboardSheet: View {
    let serial: String
    let onDismiss: () -> Void

    @State private var textToSend = ""
    @State private var isSending = false
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Push Text to Phone", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Spacer()
                Button("Close") { onDismiss() }
            }

            Text("Enter or paste text from your Mac. It will be typed directly into the active text field on your Android phone.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $textToSend)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Paste Mac Clipboard") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        textToSend = string
                    }
                }
                .controlSize(.small)

                Spacer()

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Button(action: send) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Send to Phone", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(textToSend.isEmpty || isSending)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
                textToSend = string
            }
        }
    }

    private func send() {
        isSending = true
        statusMessage = ""
        Task {
            do {
                try await ADBManager.shared.sendTextToDevice(serial: serial, text: textToSend)
                await MainActor.run {
                    self.isSending = false
                    self.statusMessage = "Sent successfully!"
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.statusMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Scrcpy Install Sheet

private struct ScrcpyInstallSheet: View {
    let onDismiss: () -> Void
    @State private var copiedCommand = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 32))
                    .foregroundColor(.purple)
            }

            VStack(spacing: 6) {
                Text("Enable Screen Mirroring")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("DroidSync uses the high-performance **scrcpy** engine for zero-latency 60fps screen display, mouse control, and typing.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Install via Homebrew in Terminal:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack {
                    Text("brew install scrcpy")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: copyCommand) {
                        Label(copiedCommand ? "Copied!" : "Copy", systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button("Open Terminal") {
                    let script = "tell application \"Terminal\" to do script \"brew install scrcpy\""
                    if let appleScript = NSAppleScript(source: script) {
                        var error: NSDictionary?
                        appleScript.executeAndReturnError(&error)
                    }
                }
                .buttonStyle(.bordered)

                Button("I've Installed It / Refresh") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install scrcpy", forType: .string)
        withAnimation {
            copiedCommand = true
        }
    }
}
