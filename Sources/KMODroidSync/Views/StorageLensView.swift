import SwiftUI

public struct StorageItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let sizeBytes: Int64

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct StorageLensView: View {
    @ObservedObject var appState: AppState
    @State private var items: [StorageItem] = []
    @State private var isScanning = false

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Lens")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Inspect large folders and clean up space on your phone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: scanStorage) {
                    Label("Scan Storage", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Calculating folder sizes on phone...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Ready to analyze storage")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Scan Internal Storage Now", action: scanStorage)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 14) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body)
                                .fontWeight(.semibold)
                            Text(item.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(item.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 100, alignment: .trailing)

                        Button("Browse") {
                            appState.navigateTo(path: item.path)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func scanStorage() {
        guard let device = appState.selectedDevice else { return }
        isScanning = true

        Task {
            do {
                // Run du -k -d 1 /sdcard to get 1st-level directory sizes
                let raw = try await ADBManager.shared.executeAdb(["-s", device.id, "shell", "du", "-k", "-d", "1", "/sdcard"])
                var list: [StorageItem] = []

                for line in raw.components(separatedBy: .newlines) {
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    guard parts.count >= 2 else { continue }

                    if let kb = Int64(parts[0]) {
                        let path = String(parts[1])
                        let name = (path as NSString).lastPathComponent
                        if name != "sdcard" && !name.isEmpty {
                            list.append(StorageItem(name: name, path: path, sizeBytes: kb * 1024))
                        }
                    }
                }

                list.sort { $0.sizeBytes > $1.sizeBytes }

                await MainActor.run {
                    self.items = list
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                }
            }
        }
    }
}
