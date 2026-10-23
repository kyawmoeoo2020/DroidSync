import SwiftUI

public struct WirelessPairView: View {
    @ObservedObject var appState: AppState
    @State private var ipAddress = ""
    @State private var pairingPort = ""
    @State private var pairingCode = ""
    @State private var connectPort = "5555"
    @State private var statusText = ""
    @State private var isProcessing = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wireless ADB Pairing")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Connect your Android phone completely wire-free over your local Wi-Fi.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Step 1: Phone instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step 1: On your Android Phone (Android 11+)")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        InstructionRow(number: "1", text: "Ensure your Mac and phone are on the **same Wi-Fi network**.")
                        InstructionRow(number: "2", text: "Go to **Settings > System > Developer options**.")
                        InstructionRow(number: "3", text: "Turn on **Wireless debugging**.")
                        InstructionRow(number: "4", text: "Tap on **'Pair device with pairing code'**.")
                        InstructionRow(number: "5", text: "Note the **IP address, port, and 6-digit pairing code** shown on screen.")
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Step 2: Input fields
                VStack(alignment: .leading, spacing: 14) {
                    Text("Step 2: Enter Pairing Credentials")
                        .font(.headline)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Phone IP Address")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("e.g. 192.168.1.105", text: $ipAddress)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 180)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pairing Port")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("e.g. 38472", text: $pairingPort)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("6-Digit Code")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("e.g. 123456", text: $pairingCode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                        }
                    }

                    HStack {
                        Button(action: pairDevice) {
                            if isProcessing {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Text("Pair Device")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ipAddress.isEmpty || pairingPort.isEmpty || pairingCode.isEmpty || isProcessing)

                        Spacer()
                    }
                }

                // Step 3: Direct Connect
                VStack(alignment: .leading, spacing: 12) {
                    Text("Already Paired? Direct Connect")
                        .font(.headline)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect Port")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Port", text: $connectPort)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                        }

                        Button("Connect via Wi-Fi") {
                            connectDirect()
                        }
                        .buttonStyle(.bordered)
                        .disabled(ipAddress.isEmpty || connectPort.isEmpty || isProcessing)
                    }
                }

                if !statusText.isEmpty {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(statusText)
                            .font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            .padding(24)
        }
    }

    private func pairDevice() {
        guard let pPort = Int(pairingPort) else { return }
        isProcessing = true
        statusText = "Pairing with \(ipAddress):\(pPort)..."

        Task {
            do {
                let res = try await ADBManager.shared.pairWireless(host: ipAddress, port: pPort, code: pairingCode)
                await MainActor.run {
                    self.statusText = "Pairing Result: \(res.trimmingCharacters(in: .whitespacesAndNewlines))"
                    self.isProcessing = false
                    self.appState.refreshDevices()
                }
            } catch {
                await MainActor.run {
                    self.statusText = "Failed to pair: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    private func connectDirect() {
        guard let cPort = Int(connectPort) else { return }
        isProcessing = true
        statusText = "Connecting to \(ipAddress):\(cPort)..."

        Task {
            do {
                let res = try await ADBManager.shared.connectWireless(host: ipAddress, port: cPort)
                await MainActor.run {
                    self.statusText = "Connect Result: \(res.trimmingCharacters(in: .whitespacesAndNewlines))"
                    self.isProcessing = false
                    self.appState.refreshDevices()
                }
            } catch {
                await MainActor.run {
                    self.statusText = "Failed to connect: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
}

private struct InstructionRow: View {
    let number: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 20, height: 20)
                Text(number)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            Text(text)
                .font(.subheadline)
        }
    }
}
