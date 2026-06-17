import SwiftUI

struct EnvironmentCheckView: View {
    let dependencies: [DependencyCheck]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("依赖检查", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
                    .foregroundColor(.primary)

                if dependencies.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("运行环境检查以查看工具链状态")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(dependencies) { dep in
                        dependencyRow(dep)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.card)
    }

    @ViewBuilder
    private func dependencyRow(_ dep: DependencyCheck) -> some View {
        HStack(spacing: 8) {
            statusIcon(dep.status)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(dep.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(dep.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            statusBadge(dep.status)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(dep.status == .warning ? Color.orange.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func statusIcon(_ status: DependencyStatus) -> some View {
        switch status {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: DependencyStatus) -> some View {
        let (text, color) = statusBadgeInfo(status)
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func statusBadgeInfo(_ status: DependencyStatus) -> (String, Color) {
        switch status {
        case .ok: return ("正常", .green)
        case .warning: return ("警告", .orange)
        case .missing: return ("缺失", .red)
        case .unknown: return ("未知", .secondary)
        }
    }
}
