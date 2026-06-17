import SwiftUI

struct LogConsoleView: View {
    let logs: [LogEntry]
    let runState: RunState
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Label("编译输出", systemImage: "terminal")
                    .font(.headline)

                Spacer()

                // 复制全部
                Button {
                    let allText = logs.map(\.text).joined()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(allText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .help("复制全部")

                Toggle("自动滚动", isOn: $autoScroll)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                // 状态指示器
                statusBadge
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 日志内容（NSTextView — 原生支持全选、部分选择、大量文本）
            if logs.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(runState == .idle ? "就绪" : "等待输出...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogTextView(logs: logs, autoScroll: $autoScroll)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 状态徽章

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(runState.displayName)
                .font(.caption)
                .fontWeight(statusFontWeight)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1), in: Capsule())
    }

    private var statusColor: Color {
        switch runState {
        case .idle: return .secondary
        case .detecting, .checkingEnvironment, .building, .flashing, .verifying: return .blue
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var statusFontWeight: Font.Weight {
        switch runState {
        case .success, .failed, .cancelled: return .bold
        default: return .regular
        }
    }
}
