import SwiftUI

struct ProjectListView: View {
    let projects: [ProjectInfo]
    let currentProject: ProjectInfo?
    let onSelect: (URL) -> Void
    let onRemove: (ProjectInfo) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Label("最近项目", systemImage: "clock")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if !projects.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "clear")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .help("清除全部")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("暂无最近项目")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("点击「选择项目」开始")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(projects) { project in
                            ProjectRow(
                                project: project,
                                isSelected: project.id == currentProject?.id,
                                onSelect: { onSelect(project.rootURL) },
                                onRemove: { onRemove(project) }
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - 项目行

struct ProjectRow: View {
    let project: ProjectInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // 选择层（不覆盖叉号按钮区域）
            HStack(spacing: 10) {
                vendorIcon
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(project.vendor.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }

            // 叉号按钮（覆盖在右上角）
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 2)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected ?
            Color.accentColor.opacity(0.08) :
            (isHovered ? Color.secondary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var vendorIcon: some View {
        switch project.vendor {
        case .stm32:
            Image(systemName: "cpu")
                .font(.system(size: 13))
                .foregroundColor(.blue)
        case .tiMSPM0:
            Image(systemName: "cpu")
                .font(.system(size: 13))
                .foregroundColor(.orange)
        case .unknown:
            Image(systemName: "questionmark")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
