import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        HSplitView {
            // 左栏：最近项目（侧边栏风格）
            ProjectListView(
                projects: appState.recentProjectStore.recentProjects,
                currentProject: appState.currentProject,
                onSelect: { url in appState.selectProjectByURL(url) },
                onRemove: { project in appState.recentProjectStore.remove(project) },
                onClear: { appState.recentProjectStore.clear() }
            )
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            // 中栏：信息 + 操作
            centerPanel
                .frame(minWidth: 360, idealWidth: 420)

            // 右栏：编译输出控制台
            LogConsoleView(logs: appState.logs, runState: appState.runState)
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView(settingsStore: appState.settingsStore, isPresented: $appState.showSettings)
        }
        .sheet(isPresented: $appState.showNewProject) {
            NewProjectView(settingsStore: appState.settingsStore, isPresented: $appState.showNewProject)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSuperFlashSettings)) { _ in
            appState.openSettings()
        }
        .onAppear {
            // 注册悬浮球快速操作回调
            let ball = FloatingBallManager.shared
            ball.onBuild = { appState.runAction(.build) }
            ball.onBuildAndFlash = { appState.runAction(.buildAndFlash) }
            ball.onVerify = { appState.runAction(.verify) }
            ball.onSwitchProject = { url in appState.selectProjectByURL(url) }
            ball.recentProjects = appState.recentProjectStore.recentProjects
            ball.activeProjectURL = appState.currentProject?.rootURL

            if appState.settingsStore.saveRecentProjects,
               !appState.recentProjectStore.recentProjects.isEmpty {
                appState.selectProjectByURL(appState.recentProjectStore.recentProjects[0].rootURL)
            }
        }
        // 同步运行状态到悬浮球
        .onChange(of: appState.runState) { _, newState in
            let ball = FloatingBallManager.shared
            switch newState {
            case .idle, .detecting, .checkingEnvironment:
                if ball.isBallMode { ball.updateStatus(.idle) }
            case .building:
                if ball.isBallMode { ball.updateStatus(.building) }
            case .flashing:
                if ball.isBallMode { ball.updateStatus(.flashing) }
            case .verifying:
                if ball.isBallMode { ball.updateStatus(.verifying) }
            case .success:
                if ball.isBallMode { ball.updateStatus(.success("操作成功")) }
            case .failed:
                if ball.isBallMode { ball.updateStatus(.failure("操作失败")) }
            case .cancelled:
                if ball.isBallMode { ball.updateStatus(.idle) }
            }
        }
        // 同步编译进度到悬浮球
        .onChange(of: appState.buildProgress) { _, progress in
            guard FloatingBallManager.shared.isBallMode else { return }
            FloatingBallManager.shared.buildProgress = progress
        }
        // 同步最近项目列表到悬浮球
        .onReceive(appState.recentProjectStore.objectWillChange) { _ in
            let ball = FloatingBallManager.shared
            ball.recentProjects = appState.recentProjectStore.recentProjects
            ball.activeProjectURL = appState.currentProject?.rootURL
        }
        // 当前项目变更时同步到悬浮球（切换项目后弹窗立即反映新状态）
        .onChange(of: appState.currentProject?.rootURL) { _, newURL in
            FloatingBallManager.shared.activeProjectURL = newURL
        }
    }

    // MARK: - 中间面板

    @ViewBuilder
    private var centerPanel: some View {
        VStack(spacing: 0) {
            // 状态横幅（操作中 / 完成 / 失败）
            StatusBannerView(runState: appState.runState)

            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    // 项目信息卡片
                    ProjectSummaryView(project: appState.currentProject)

                    // 操作按钮面板
                    if appState.currentProject != nil {
                        actionButtonPanel
                    }

                    // 依赖检查
                    if appState.currentProject?.isDetected == true {
                        EnvironmentCheckView(dependencies: appState.dependencies)
                    }

                    // 诊断信息（有内容或失败时显示）
                    if !appState.diagnostics.isEmpty || appState.runState.isFailed {
                        DiagnosticView(diagnostics: appState.diagnostics)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .overlay(alignment: .topTrailing) {
            // 悬浮球切换按钮 — 界面右上角
            Button {
                FloatingBallManager.shared.toggle()
            } label: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 28, height: 28)
                    )
            }
            .buttonStyle(.plain)
            .help("切换悬浮球 (⇧⌘M)")
            .padding(6)
        }
        .animation(.easeInOut(duration: 0.25), value: appState.runState)
    }

    // MARK: - 操作按钮面板

    @ViewBuilder
    private var actionButtonPanel: some View {
        VStack(spacing: 0) {
            // 第一行：项目操作
            HStack(spacing: 10) {
                ToolbarActionButton(title: "新建项目", icon: "plus.square", action: { appState.showNewProject = true })
                    .help("创建新项目")

                ToolbarActionButton(title: "选择项目", icon: "folder.badge.plus", action: appState.selectProject)
                    .help("选择嵌入式项目目录")

                if appState.currentProject?.isDetected == true {
                    ToolbarActionButton(title: "重新检测", icon: "arrow.triangle.2.circlepath", action: appState.redetectCurrentProject)
                        .help("重新分析当前项目")

                    ToolbarActionButton(title: "检查环境", icon: "wrench.and.screwdriver", action: appState.checkEnvironment)
                        .help("检查工具链依赖")
                }

                Spacer()

                if appState.runState.inProgress {
                    CancelButton(action: appState.cancelTask)
                }
            }

            if appState.currentProject?.isDetected == true && appState.currentProject?.vendor != .unknown {
                Divider()
                    .padding(.vertical, 10)

                // 第二行：编译烧录操作
                HStack(spacing: 12) {
                    BuildActionButton(title: "编译", icon: "hammer.fill",
                                      action: { appState.runAction(.build) },
                                      disabled: appState.runState.inProgress)
                    BuildActionButton(title: "烧录", icon: "memorychip.fill",
                                      action: { appState.runAction(.flash) },
                                      disabled: appState.runState.inProgress)
                    BuildActionButton(title: "编译并烧录", icon: "bolt.fill",
                                      action: { appState.runAction(.buildAndFlash) },
                                      disabled: appState.runState.inProgress,
                                      prominent: true)
                    BuildActionButton(title: "验证连接", icon: "antenna.radiowaves.left.and.right",
                                      action: { appState.runAction(.verify) },
                                      disabled: appState.runState.inProgress)
                }

                // 工具按钮行
                HStack(spacing: 6) {
                    Spacer()
                    ToolButton(icon: "trash", title: "清除日志", action: appState.clearLogs)
                    ToolButton(icon: "folder", title: "打开编译产物", action: appState.openArtifacts)
                    ToolButton(icon: "doc.text", title: "打开报告", action: appState.openReport)
                    ToolButton(icon: "doc.on.clipboard", title: "复制诊断信息", action: appState.copyDiagnostics)
                    ToolButton(icon: "gearshape", title: "设置", action: appState.openSettings)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - 子组件

/// 工具栏按钮（图标 + 文字）
struct ToolbarActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .foregroundColor(isHovered ? .accentColor : .primary)
        .onHover { isHovered = $0 }
        .background(
            isHovered ?
            Color.accentColor.opacity(0.1) :
            Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

/// 编译/烧录操作按钮
struct BuildActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var disabled: Bool = false
    var prominent: Bool = false

    var body: some View {
        if prominent {
            Button(action: action) {
                label
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .controlSize(.large)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(BorderedButtonStyle())
            .controlSize(.large)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
        }
    }

    private var label: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.caption2)
        }
        .frame(minWidth: 56, minHeight: 48)
    }
}

/// 工具按钮（纯图标）
struct ToolButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundColor(isHovered ? .accentColor : .secondary)
        .onHover { isHovered = $0 }
        .help(title)
    }
}

/// 取消按钮（操作中显示）
struct CancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text("取消")
                    .font(.subheadline)
            }
            .frame(minWidth: 60)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
    }
}

// MARK: - RunState 辅助

extension RunState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
