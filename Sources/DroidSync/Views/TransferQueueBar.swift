import SwiftUI

public struct TransferQueueBar: View {
    @ObservedObject var transferManager = TransferManager.shared
    @State private var isExpanded = false

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 14) {
                if let active = transferManager.activeTasks.first(where: { $0.status == .transferring }) ?? transferManager.activeTasks.first {
                    // Direction Icon Badge
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: active.direction.systemImageName)
                            .foregroundColor(.accentColor)
                            .font(.system(size: 15, weight: .semibold))
                    }

                    // Task Info & Progress
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(active.direction == .download ? "Downloading" : "Uploading")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentColor)

                            Text(active.filename)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let subfile = active.currentSubfile, !subfile.isEmpty {
                                Text("›  \(subfile)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            // Transferred bytes of total
                            Text(active.formattedProgress)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            // Percentage
                            Text(active.percentageText)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }

                        // Realtime Smooth Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 5)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(5, geo.size.width * CGFloat(active.progressFraction)), height: 5)
                                    .animation(.linear(duration: 0.08), value: active.progressFraction)
                            }
                        }
                        .frame(height: 5)

                        // Sub-row: Speed, ETA, Queue remaining
                        HStack(spacing: 8) {
                            Label(active.formattedSpeed, systemImage: "bolt.fill")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary)

                            if !active.formattedETA.isEmpty {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Label(active.formattedETA, systemImage: "clock")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }

                            if transferManager.activeTasks.count > 1 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("\(transferManager.activeTasks.count) items in queue")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Cancel Active Task Button
                    Button(action: {
                        transferManager.cancelTask(id: active.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Cancel active transfer")

                } else if !transferManager.completedTasks.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                    Text("All transfers complete (\(transferManager.completedTasks.count) files)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                } else {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    Text("No active transfers")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                // Queue Buttons
                if !transferManager.tasks.isEmpty {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Hide Queue" : "View Queue (\(transferManager.tasks.count))")
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                                .font(.system(size: 9))
                        }
                        .font(.caption)
                    }

                    Button("Clear") {
                        transferManager.clearCompleted()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            // Expanded Queue Drawer
            if isExpanded {
                Divider()

                VStack(spacing: 0) {
                    // Drawer Header
                    HStack {
                        Text("Transfers (\(transferManager.tasks.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        if !transferManager.activeTasks.isEmpty {
                            Button("Cancel All") {
                                transferManager.cancelAll()
                            }
                            .font(.caption2)
                            .foregroundColor(.red)
                        }

                        Button("Clear Done") {
                            transferManager.clearCompleted()
                        }
                        .font(.caption2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(transferManager.tasks) { task in
                                HStack(spacing: 10) {
                                    // Status icon
                                    Group {
                                        switch task.status {
                                        case .completed:
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        case .transferring:
                                            Image(systemName: task.direction.systemImageName)
                                                .foregroundColor(.accentColor)
                                        case .queued:
                                            Image(systemName: "clock")
                                                .foregroundColor(.secondary)
                                        case .failed:
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundColor(.red)
                                        case .cancelled:
                                            Image(systemName: "slash.circle")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .font(.system(size: 14))
                                    .frame(width: 18)

                                    // Details
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(task.filename)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .lineLimit(1)

                                            if task.status == .transferring {
                                                Text("• \(task.percentageText)")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.accentColor)
                                            }
                                        }

                                        HStack(spacing: 6) {
                                            Text(task.formattedProgress)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            if task.status == .transferring {
                                                Text("• \(task.formattedSpeed)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)

                                                if !task.formattedETA.isEmpty {
                                                    Text("• \(task.formattedETA)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else if task.status == .completed && task.speedBytesPerSec > 0 {
                                                Text("• avg \(task.formattedSpeed)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            } else if task.status == .failed, let err = task.errorMessage {
                                                Text("• \(err)")
                                                    .font(.caption2)
                                                    .foregroundColor(.red)
                                                    .lineLimit(1)
                                            }
                                        }

                                        if task.status == .transferring {
                                            ProgressView(value: task.progressFraction)
                                                .progressViewStyle(LinearProgressViewStyle())
                                                .frame(maxWidth: .infinity)
                                                .padding(.top, 1)
                                        }
                                    }

                                    Spacer()

                                    // Status Badge & Action
                                    HStack(spacing: 8) {
                                        Text(task.status.rawValue)
                                            .font(.caption2)
                                            .foregroundColor(
                                                task.status == .completed ? .green :
                                                (task.status == .failed ? .red :
                                                (task.status == .transferring ? .accentColor : .secondary))
                                            )

                                        if task.status == .transferring || task.status == .queued {
                                            Button(action: {
                                                transferManager.cancelTask(id: task.id)
                                            }) {
                                                Image(systemName: "xmark.circle")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .help("Cancel task")
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 180)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
        }
    }
}
