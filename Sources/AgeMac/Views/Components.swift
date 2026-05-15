import AppKit
import SwiftUI

struct GlassCard<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(16)
        .modifier(GlassSurface())
    }
}

struct GlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

struct PageHeader: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(store.settings.theme.accentColor)
                .frame(width: 42, height: 42)
                .modifier(GlassSurface())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct FileListView: View {
    var files: [SelectedFile]
    var onRemove: (SelectedFile) -> Void

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView("没有文件", systemImage: "doc.badge.plus", description: Text("使用上方按钮添加文件"))
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            List(files) { file in
                HStack(spacing: 10) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(1)
                        Text("\(AppFormatters.fileSize(file.size)) · \(AppFormatters.shortPath(file.path))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        onRemove(file)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("移除")
                }
                .padding(.vertical, 3)
            }
            .frame(minHeight: 180)
        }
    }
}

struct TaskStatusCard: View {
    @EnvironmentObject private var store: AppStore
    var task: RunningOperation?
    var onRemove: () -> Void

    var body: some View {
        if let task {
            GlassCard {
                HStack {
                    Label(task.title, systemImage: task.kind.systemImage)
                        .font(.headline)
                    Spacer()
                    Text(task.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(task.status))
                    if task.status != .running {
                        Button(role: .destructive) {
                            onRemove()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("删除结果")
                    }
                }

                ProgressView(value: min(max(task.progress, 0), 1))

                HStack {
                    Text(task.phase)
                    Spacer()
                    Text("\(task.processed)/\(max(task.total, 1))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if task.success > 0 || task.fail > 0 {
                    HStack(spacing: 12) {
                        Label("\(task.success)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("\(task.fail)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                }

                if let message = task.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if !task.outputs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(task.outputs.prefix(4), id: \.self) { output in
                            Button {
                                store.reveal(path: output)
                            } label: {
                                Label(AppFormatters.shortPath(output), systemImage: "arrow.up.right.square")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                if task.status == .running {
                    Button(role: .destructive) {
                        store.cancelCurrentTask()
                    } label: {
                        Label("取消任务", systemImage: "stop.circle")
                    }
                }
            }
        }
    }

    private func statusColor(_ status: OperationStatus) -> Color {
        switch status {
        case .running: store.settings.theme.accentColor
        case .success: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}

struct PrimaryActionCell: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var disabled: Bool
    var action: () -> Void
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .opacity(disabled ? 0.72 : 0.84)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .opacity(disabled ? 0.38 : 0.9)
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var backgroundFill: some ShapeStyle {
        if disabled {
            AnyShapeStyle(.regularMaterial)
        } else {
            AnyShapeStyle(LinearGradient(
                colors: [store.settings.theme.accentColor, store.settings.theme.secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
    }

    private var foregroundStyle: Color {
        disabled ? .secondary : .white
    }

    private var iconBackground: Color {
        disabled ? Color.secondary.opacity(0.12) : Color.white.opacity(0.18)
    }

    private var borderColor: Color {
        disabled ? Color.secondary.opacity(0.22) : Color.white.opacity(0.22)
    }
}

extension AppTheme {
    var accentColor: Color {
        switch self {
        case .teal: .teal
        case .indigo: .indigo
        case .violet: .purple
        case .rose: .pink
        case .amber: .orange
        case .graphite: .gray
        }
    }

    var secondaryColor: Color {
        switch self {
        case .teal: .indigo
        case .indigo: .cyan
        case .violet: .teal
        case .rose: .orange
        case .amber: .blue
        case .graphite: .teal
        }
    }

    var swatchColors: [Color] {
        [accentColor, secondaryColor]
    }
}

struct KeyPicker: View {
    var title: String
    var keys: [KeyEntry]
    @Binding var selection: UUID?
    var requiresPrivateKey: Bool

    var eligibleKeys: [KeyEntry] {
        requiresPrivateKey ? keys.filter(\.hasPrivateKey) : keys
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("不使用已保存密钥").tag(UUID?.none)
            ForEach(eligibleKeys) { key in
                Text(key.name).tag(Optional(key.id))
            }
        }
    }
}

struct FocusClearingOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var monitor: Any?

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                guard let window = event.window,
                      window.isKeyWindow,
                      NSApp.isActive,
                      let contentView = window.contentView else {
                    return event
                }
                guard window.firstResponder?.isTextEntryResponder == true else {
                    return event
                }

                let location = contentView.convert(event.locationInWindow, from: nil)
                guard contentView.bounds.contains(location),
                      !contentView.containsTextEditingControl(at: location) else {
                    return event
                }

                DispatchQueue.main.async {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private extension NSResponder {
    var isTextEntryResponder: Bool {
        if self is NSTextView || self is NSTextField {
            return true
        }
        return (self as? NSView)?.isTextEditingControl == true
    }
}

private extension NSView {
    var isTextEditingControl: Bool {
        if self is NSTextView || self is NSTextField {
            return true
        }
        return superview?.isTextEditingControl ?? false
    }

    func containsTextEditingControl(at point: NSPoint) -> Bool {
        guard !isHidden, alphaValue > 0 else { return false }
        if bounds.contains(point), isTextEditingControl {
            return true
        }

        for subview in subviews.reversed() {
            let localPoint = subview.convert(point, from: self)
            guard subview.bounds.contains(localPoint) else { continue }
            if subview.containsTextEditingControl(at: localPoint) {
                return true
            }
        }
        return false
    }
}
