/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let strings = store.strings

        PageHeader(
            title: AppSection.history.title(in: store.settings.language),
            subtitle: strings.historySubtitle,
            systemImage: "clock.arrow.circlepath"
        )

        GlassCard {
            HStack {
                Label(strings.historyTitle, systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    store.clearHistory()
                } label: {
                    Label(strings.clear, systemImage: "trash")
                }
                .disabled(store.operations.isEmpty)
            }

            if store.operations.isEmpty {
                ContentUnavailableView(strings.noHistoryTitle, systemImage: "clock", description: Text(strings.noHistoryDescription))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(store.operations) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(record.kind.title(in: store.settings.language), systemImage: record.kind.systemImage)
                                .font(.headline)
                            Text(record.modeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(record.status.title(in: store.settings.language))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(record.status))
                            Button(role: .destructive) {
                                store.removeOperation(id: record.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(strings.deleteRecord)
                        }

                        Text(record.inputFiles.prefix(4).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let details = record.details {
                            let items = details.summaryItems(in: store.settings.language)
                            Text((items + [strings.inputFileCount(details.inputCount)]).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Text(AppFormatters.dateTime(record.timestamp, language: store.settings.language))
                            Spacer()
                            if let output = record.outputs.first {
                                Button {
                                    store.reveal(path: output)
                                } label: {
                                    Label(strings.outputCount(record.outputs.count), systemImage: "arrow.up.right.square")
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
