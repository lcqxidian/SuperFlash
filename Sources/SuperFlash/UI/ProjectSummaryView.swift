import SwiftUI

struct ProjectSummaryView: View {
    let project: ProjectInfo?

    var body: some View {
        GroupBox {
            if let project {
                VStack(alignment: .leading, spacing: 12) {
                    // 项目名称 + 供应商标签
                    HStack {
                        Text(project.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Spacer()

                        vendorBadge(project.vendor)
                    }

                    if project.isDetected {
                        Divider()

                        // 详细信息网格
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ], spacing: 6) {
                            infoRow(icon: "doc.badge.gearshape", label: "种类", value: project.projectKind.displayName)
                            if let chip = project.chipName {
                                infoRow(icon: "microchip", label: "芯片", value: chip)
                            }
                            infoRow(icon: "hammer", label: "编译方式", value: project.buildMethod)
                            infoRow(icon: "memorychip", label: "烧录方式", value: project.flashMethod)
                            infoRow(icon: "doc.text", label: "源文件", value: "\(project.sourceCount) 个")
                            infoRow(icon: "text.alignleft", label: "头文件", value: "\(project.includeCount) 个")
                        }

                        if project.makefile != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("包含 Makefile")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("无法识别项目类型")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("未选择项目")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("点击上方「选择项目」按钮开始")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .groupBoxStyle(.card)
    }

    @ViewBuilder
    private func vendorBadge(_ vendor: ProjectVendor) -> some View {
        let (name, color) = vendorBadgeInfo(vendor)
        Text(name)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    private func vendorBadgeInfo(_ vendor: ProjectVendor) -> (String, Color) {
        switch vendor {
        case .stm32: return ("STM32", .blue)
        case .tiMSPM0: return ("TI MSPM0", .orange)
        case .unknown: return ("未知", .gray)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }
}

// MARK: - Card GroupBox Style

struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.content
                .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

extension GroupBoxStyle where Self == CardGroupBoxStyle {
    static var card: CardGroupBoxStyle { CardGroupBoxStyle() }
}
