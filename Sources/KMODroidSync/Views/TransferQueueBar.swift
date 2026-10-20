import SwiftUI

public struct TransferQueueBar: View {
    @ObservedObject var transferManager = TransferManager.shared
    @State private var isExpanded = false

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                if let active = transferManager.activeTasks.first {
                    Image(systemName: active.direction.systemImageName)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(active.direction == .download ? "Downloading" : "Uploading")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text(active.filename)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        ProgressView(value: active.progressFraction)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 220)
                    }

                    Text(active.formattedSpeed)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                } else if !transferManager.completedTasks.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All transfers complete (\(transferManager.completedTasks.count) files)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundColor(.secondary)
                    Text("No active transfers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !transferManager.tasks.isEmpty {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Text(isExpanded ? "Hide Queue" : "View Queue (\(transferManager.tasks.count))")
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

            if isExpanded {
                Divider()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(transferManager.tasks) { task in
                            HStack(spacing: 8) {
                                Image(systemName: task.direction.systemImageName)
                                    .foregroundColor(task.status == .completed ? .green : (task.status == .failed ? .red : .accentColor))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.filename)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(task.formattedProgress)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(task.status.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(task.status == .completed ? .green : .secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 140)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
}
