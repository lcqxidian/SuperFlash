import SwiftUI

struct ActionBarView: View {
    let runState: RunState
    let vendor: ProjectVendor
    let hasProject: Bool
    let onSelect: () -> Void
    let onRedetect: () -> Void
    let onCheckEnv: () -> Void
    let onBuild: () -> Void
    let onFlash: () -> Void
    let onBuildFlash: () -> Void
    let onVerify: () -> Void
    let onCancel: () -> Void
    let onOpenReport: () -> Void
    let onOpenArtifacts: () -> Void
    let onCopyDiag: () -> Void
    let onClearLogs: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 项目选择
            Button("选择项目", action: onSelect)
                .help("选择嵌入式项目目录")

            if hasProject {
                Button("重新检测", action: onRedetect)
                    .help("重新分析当前项目")

                Button("检查环境", action: onCheckEnv)
                    .help("检查工具链依赖")
            }

            Divider()

            if runState.inProgress {
                Button("取消", role: .cancel, action: onCancel)
                    .help("取消当前操作")
            } else {
                // 操作按钮
                if hasProject && vendor != .unknown {
                    buildActionButtons
                }

                Divider()

                // 工具按钮
                Button(action: onClearLogs) {
                    Image(systemName: "trash")
                }
                .help("清除日志")

                if hasProject {
                    Button(action: onOpenArtifacts) {
                        Image(systemName: "folder")
                    }
                    .help("打开编译产物")

                    Button(action: onOpenReport) {
                        Image(systemName: "doc.text")
                    }
                    .help("打开报告")

                    Button(action: onCopyDiag) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("复制诊断信息")
                }

                Spacer()

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .help("设置")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var buildActionButtons: some View {
        Button("编译", action: onBuild)
        Button("烧录", action: onFlash)
        Button("编译并烧录", action: onBuildFlash)
            .buttonStyle(.borderedProminent)
        Button("验证", action: onVerify)
    }
}
