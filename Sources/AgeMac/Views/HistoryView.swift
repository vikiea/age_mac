/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        PageHeader(title: "历史", subtitle: "查看本机加密和解密操作记录", systemImage: "clock.arrow.circlepath")

        GlassCard {
            HStack {
                Label("操作记录", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    store.clearHistory()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .disabled(store.operations.isEmpty)
            }

            if store.operations.isEmpty {
                ContentUnavailableView("没有历史记录", systemImage: "clock", description: Text("完成一次任务后会出现在这里"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(store.operations) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(record.kind.title, systemImage: record.kind.systemImage)
                                .font(.headline)
                            Text(record.modeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(record.status.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(record.status))
                            Button(role: .destructive) {
                                store.removeOperation(id: record.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("删除记录")
                        }

                        Text(record.inputFiles.prefix(4).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack {
                            Text(AppFormatters.dateTime.string(from: record.timestamp))
                            Spacer()
                            if let output = record.outputs.first {
                                Button {
                                    store.reveal(path: output)
                                } label: {
                                    Label("显示输出", systemImage: "arrow.up.right.square")
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let error = record.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }

    private func color(_ status: OperationStatus) -> Color {
        switch status {
        case .running: .teal
        case .success: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}
