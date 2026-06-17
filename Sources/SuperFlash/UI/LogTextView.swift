import SwiftUI
import AppKit

/// macOS NSTextView 包装 — 支持 Cmd+A 全选、部分选择、大量文本高效渲染
struct LogTextView: NSViewRepresentable {
    let logs: [LogEntry]
    @Binding var autoScroll: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.update(textView: textView, logs: logs, autoScroll: autoScroll)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var lastLogCount = 0
        private var pendingScroll = false

        @MainActor
        func update(textView: NSTextView, logs: [LogEntry], autoScroll: Bool) {
            // 日志没变化则不刷新
            guard logs.count != lastLogCount || logs.isEmpty else { return }
            lastLogCount = logs.count

            let attr = NSMutableAttributedString()
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

            for entry in logs {
                let color = logColor(entry.text)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                ]
                attr.append(NSAttributedString(string: entry.text, attributes: attrs))
            }

            textView.textStorage?.setAttributedString(attr)

            if autoScroll || pendingScroll {
                pendingScroll = false
                textView.scrollToEndOfDocument(nil)
            }
        }

        private func logColor(_ text: String) -> NSColor {
            let lower = text.lowercased()
            if lower.contains("error") || lower.contains("fail") || lower.contains("fatal") { return .systemRed }
            if lower.contains("warning") { return .systemOrange }
            if lower.contains("success") || lower.contains("ok") || lower.contains("verified") || lower.contains("completed") { return .systemGreen }
            if lower.contains("[cancel") || lower.contains("[已取消") { return .systemOrange }
            return .textColor
        }
    }
}
