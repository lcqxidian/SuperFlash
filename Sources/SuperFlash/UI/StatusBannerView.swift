import SwiftUI

/// 状态横幅 — 操作中显示进度，完成时显示成功/失败
struct StatusBannerView: View {
    let runState: RunState

    var body: some View {
        Group {
            switch runState {
            case .detecting:
                progressContent(text: "正在检测项目...", icon: "magnifyingglass")
            case .checkingEnvironment:
                progressContent(text: "正在检查环境...", icon: "wrench.and.screwdriver")
            case .building:
                progressContent(text: "正在编译...", icon: "hammer.fill")
            case .flashing:
                progressContent(text: "正在烧录...", icon: "memorychip.fill")
            case .verifying:
                progressContent(text: "正在验证...", icon: "antenna.radiowaves.left.and.right")
            case .success:
                resultContent(icon: "checkmark.circle.fill", text: "操作成功完成！", color: .green)
            case .failed(let reason):
                resultContent(icon: "xmark.circle.fill", text: reason.isEmpty ? "操作失败" : "失败：\(reason)", color: .red)
            case .cancelled:
                resultContent(icon: "xmark.circle.fill", text: "操作已取消", color: .orange)
            case .idle:
                EmptyView()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// 进行中状态：进度指示器 + 动画
    private func progressContent(text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.9)

            Image(systemName: icon)
                .font(.caption)

            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Text("处理中...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.accentColor.opacity(0.12),
                    Color.accentColor.opacity(0.06),
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    /// 完成状态：颜色 + SF Symbol
    private func resultContent(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.multicolor)
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(color)
    }
}
