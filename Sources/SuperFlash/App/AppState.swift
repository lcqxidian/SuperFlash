import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var currentProject: ProjectInfo?
    @Published var toolchainInfo = ToolchainInfo()
    @Published var dependencies: [DependencyCheck] = []
    @Published var diagnostics: [DiagnosticIssue] = []
    /// 统一 setter：更新 runState 后立即同步悬浮球状态（不依赖 View .onChange）
    var runState: RunState {
        get { _runState }
        set {
            objectWillChange.send()
            _runState = newValue
            print("[AppState] runState → \(newValue)")
            syncBallStatus(newValue)
        }
    }
    private var _runState: RunState = .idle
    @Published var logs: [LogEntry] = []
    @Published var showSettings = false
    @Published var showNewProject = false
    @Published var buildProgress: Double = 0

    let detector = ProjectDetector()
    let environmentChecker = EnvironmentChecker()
    let logParser = LogParser()
    let reportStore = ReportStore()
    let planGenerator = BuildPlanGenerator()
    let settingsStore = SettingsStore()
    let recentProjectStore = RecentProjectStore()

    private let scriptRunner = ScriptRunner()
    private var cancellables = Set<AnyCancellable>()
    private var projectWatcher: DispatchSourceFileSystemObject?
    private var projectWatcherQueue = DispatchQueue(label: "com.superflash.projectwatcher")

    /// 日志节流：避免每行编译输出都触发 UI 刷新
    private var logBuffer = ""
    private var logFlushTask: Task<Void, Never>?
    private let maxLogEntries = 500

    /// 进度追踪：统计命令行完成数
    private var progressAccumulated = ""
    private var progressLastCmdCount = 0
    private var progressTotalSteps: Double = 20

    /// 任务代际计数器：防止旧进程 completionHandler 污染新任务状态
    private var taskGeneration: UInt = 0

    /// 上次烧录的项目路径，用于检测项目切换
    private var lastFlashedProjectURL: URL?

    init() {
        // 转发 RecentProjectStore 的变化到 AppState，确保 UI 刷新
        recentProjectStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var allLogText: String {
        logs.map(\.text).joined()
    }

    // MARK: - Project Selection

    func selectProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "选择嵌入式项目目录"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        scriptRunner.cancel()
        clearLogs()
        runState = .detecting

        let info = detector.detectProject(at: url)
        currentProject = info
        if settingsStore.saveRecentProjects {
            recentProjectStore.add(info)
        }

        if info.vendor != .unknown {
            runState = .idle
            log("[检测] 项目：\(info.displayName)")
            log("[检测] 供应商：\(info.vendor.displayName)")
            log("[检测] 种类：\(info.projectKind.displayName)")
            if let chip = info.chipName {
                log("[检测] 芯片：\(chip)")
            }
            log("[检测] 源文件数：\(info.sourceCount)，头文件数：\(info.includeCount)")
            if info.makefile != nil { log("[检测] 发现 Makefile") }
            if info.keilProject != nil { log("[检测] 发现 Keil 项目") }
        } else {
            runState = .failed("无法检测项目类型")
            diagnostics = [DiagnosticIssue(
                title: "未知项目类型",
                detail: "在 '\(url.lastPathComponent)' 中未找到可识别的嵌入式项目文件。",
                suggestion: "请确保项目包含可识别的 STM32 或 TI MSPM0 文件（.ioc、.uvprojx、startup_stm32*.s、ti_msp_dl_config.c、.syscfg 等）。"
            )]
        }
    }

    func redetectCurrentProject() {
        guard let project = currentProject else { return }
        scriptRunner.cancel()
        clearLogs()
        runState = .detecting

        let info = detector.detectProject(at: project.rootURL)
        currentProject = info
        if settingsStore.saveRecentProjects {
            recentProjectStore.add(info)
        }

        if info.vendor != .unknown {
            runState = .idle
            log("[重新检测] 项目已重新分析：\(info.displayName)")
            log("[重新检测] 供应商：\(info.vendor.displayName)")
            log("[重新检测] 种类：\(info.projectKind.displayName)")
            if let chip = info.chipName {
                log("[重新检测] 芯片：\(chip)")
            }
        } else {
            runState = .failed("无法检测项目类型")
        }
    }

    // MARK: - Environment Check

    func checkEnvironment() {
        runState = .checkingEnvironment
        diagnostics = []
        clearLogs()
        log("[环境检查] 开始检查环境...")

        let vendor = currentProject?.vendor ?? .unknown

        Task {
            let info = await environmentChecker.checkAll(
                armGccOverride: settingsStore.armGccPath,
                openocdOverride: settingsStore.openocdPath,
                tiArmClangOverride: settingsStore.tiArmClangPath,
                mspm0SDKOverride: settingsStore.mspm0SDKPath,
                jlinkOverride: settingsStore.jlinkPath
            )
            toolchainInfo = info
            dependencies = buildDependencyList(info: info, vendor: vendor)
            logDependencyResults(info: info, vendor: vendor)

            var issues: [DiagnosticIssue] = []
            if vendor == .stm32 || vendor == .unknown {
                if info.armGcc == nil {
                    issues.append(DiagnosticIssue(title: "未找到 ARM GCC", detail: "未找到 arm-none-eabi-gcc。", suggestion: "通过 Homebrew 安装：brew install arm-none-eabi-gcc"))
                }
                if info.openocd == nil {
                    issues.append(DiagnosticIssue(title: "未找到 OpenOCD", detail: "未找到 openocd。", suggestion: "通过 Homebrew 安装：brew install openocd"))
                }
            }
            if vendor == .tiMSPM0 || vendor == .unknown {
                if info.tiArmClang == nil {
                    issues.append(DiagnosticIssue(title: "未找到 TI Arm Clang", detail: "未找到 tiarmclang。", suggestion: "安装 TI CCS/Theia 或在设置中设置自定义路径。"))
                }
                if info.mspm0SDK == nil {
                    issues.append(DiagnosticIssue(title: "未找到 MSPM0 SDK", detail: "未找到 MSPM0 SDK。", suggestion: "安装 MSPM0 SDK 或在设置中设置自定义路径。"))
                }
                if info.jlinkExe == nil {
                    issues.append(DiagnosticIssue(title: "未找到 JLinkExe", detail: "未找到 J-Link Commander。", suggestion: "安装 SEGGER J-Link 软件或在设置中设置自定义路径。"))
                }
            }

            diagnostics = issues
            if issues.isEmpty {
                log("[环境检查] 所有依赖均已找到。")
                runState = .success
            } else {
                log("[环境检查] 发现 \(issues.count) 个问题 - 请查看诊断信息。")
                runState = .idle
            }
        }
    }

    // MARK: - Build / Flash / Verify

    func runAction(_ action: BuildAction) {
        guard let project = currentProject, let vendor = project.vendor as ProjectVendor?, vendor != .unknown else {
            runState = .failed("未选择项目或供应商未知")
            return
        }
        guard let scriptName = planGenerator.selectScript(for: vendor) else {
            runState = .failed("没有适用于 \(vendor.displayName) 的脚本")
            return
        }
        guard let scriptURL = bundledScriptURL(scriptName: scriptName) else {
            runState = .failed("未找到脚本 '\(scriptName).py'")
            diagnostics = [DiagnosticIssue(
                title: "未找到脚本",
                detail: "资源中缺少 \(scriptName).py。",
                suggestion: "请确保 Resources/scripts/ 已打包。"
            )]
            return
        }

        // 手动重置（不调用 clearLogs，避免 runState 经过 .idle）
        logFlushTask?.cancel()
        logFlushTask = nil
        logBuffer = ""
        logs = []
        diagnostics = []
        buildProgress = 0

        // 先更新悬浮球状态（直接同步，不依赖 .onChange）
        let ball = FloatingBallManager.shared
        let ballStatus: BallStatus
        switch action {
        case .build: ballStatus = .building; runState = .building
        case .flash: ballStatus = .flashing; runState = .flashing
        case .buildAndFlash: ballStatus = .building; runState = .building
        case .verify: ballStatus = .verifying; runState = .verifying
        }
        if ball.isBallMode { ball.updateStatus(ballStatus) }

        log("[\(vendor.rawValue)] 开始 \(action.displayName)...")
        log("[\(vendor.rawValue)] 脚本：\(scriptURL.lastPathComponent)")
        log("[\(vendor.rawValue)] 项目：\(project.rootURL.path)")

        // 初始化真实进度追踪（编译 + 烧录双阶段）
        let srcCount = max(project.sourceCount, 1)
        switch action {
        case .build:
            progressTotalSteps = Double(srcCount + 5)
        case .buildAndFlash:
            progressTotalSteps = Double(srcCount + 5 + 8) // 编译 + 烧录
        case .flash, .verify:
            progressTotalSteps = 8 // 烧录/验证独立步骤
        }
        buildProgress = 0
        progressAccumulated = ""
        progressLastCmdCount = 0

        // Build extra arguments from settings
        let extraArgs = buildScriptArguments(vendor: vendor)

        // 任务代际：旧 completionHandler 跳过此次更新
        taskGeneration &+= 1
        let gen = taskGeneration

        scriptRunner.outputHandler = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.logs.append(LogEntry(text: text))
                // 统计命令行完成数来计算真实进度
                self.progressAccumulated += text
                let lines = self.progressAccumulated.components(separatedBy: "\n")
                let cmdCount = lines.filter { $0.contains(" $ ") }.count
                let newCmds = cmdCount - self.progressLastCmdCount
                if newCmds > 0 {
                    self.progressLastCmdCount = cmdCount
                    self.buildProgress = self.buildProgress + Double(newCmds) / self.progressTotalSteps
                }
            }
        }

        scriptRunner.completionHandler = { [weak self, gen] exitCode, _ in
            DispatchQueue.main.async {
                guard let self, self.taskGeneration == gen else { return }
                // 记录已烧录项目（用于探针预热判定）
                if action == .buildAndFlash || action == .flash {
                    self.lastFlashedProjectURL = project.rootURL
                }
                let fullLog = self.allLogText
                if exitCode == 0 {
                    let verified = self.logParser.checkSuccess(log: fullLog, action: action)
                    if verified || fullLog.contains("Nothing to be done") {
                        print("[AppState] CompletionHandler: VERIFIED → success")
                        self.runState = .success
                        self.buildProgress = 1
                        if FloatingBallManager.shared.isBallMode { FloatingBallManager.shared.updateStatus(.success("操作成功")) }
                        self.log("[\(vendor.rawValue)] 已完成。")
                        self.diagnostics = self.logParser.parseDiagnostics(log: fullLog, vendor: vendor, succeeded: true)
                    } else {
                        // exit 0 but no success signal in log — warning
                        self.runState = .success
                        self.buildProgress = 1
                        if FloatingBallManager.shared.isBallMode { FloatingBallManager.shared.updateStatus(.success("操作成功")) }
                        self.log("[\(vendor.rawValue)] 进程退出码为 0，但输出可能存在问题。")
                        self.diagnostics = self.logParser.parseDiagnostics(log: fullLog, vendor: vendor)
                        if self.diagnostics.isEmpty {
                            self.diagnostics.append(DiagnosticIssue(
                                title: "输出中可能存在错误",
                                detail: "进程已完成（退出码 0），但未检测到明确的成功信号。",
                                suggestion: "请查看上方完整日志输出以确认警告或错误。"
                            ))
                        }
                    }
                } else {
                    self.runState = .failed("进程退出，代码 \(exitCode)")
                    self.buildProgress = 1
                    if FloatingBallManager.shared.isBallMode { FloatingBallManager.shared.updateStatus(.failure("操作失败")) }
                    self.log("[\(vendor.rawValue)] 失败，退出代码 \(exitCode)。")
                    self.diagnostics = self.logParser.parseDiagnostics(log: fullLog, vendor: vendor)
                }
            }
        }

        // TI/SAM-ICE 的冷启动预热已确认无效，并会额外增加首次烧录耗时。
        // STM32 仍保留原有 OpenOCD 预热行为。
        if action != .build, vendor == .stm32, project.rootURL != lastFlashedProjectURL {
            scriptRunner.warmupProbe(vendor: vendor)
        }

        scriptRunner.run(
            script: scriptURL,
            project: project.rootURL,
            action: action,
            envOverrides: settingsStore.envOverrides,
            extraArguments: extraArgs
        )
    }

    private func bundledScriptURL(scriptName: String) -> URL? {
        if let appResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("scripts")
            .appendingPathComponent("\(scriptName).py"),
           FileManager.default.fileExists(atPath: appResourceURL.path) {
            return appResourceURL
        }

        return Bundle.module.url(
            forResource: scriptName,
            withExtension: "py",
            subdirectory: "scripts"
        )
    }

    /// Build CLI arguments from settings based on vendor
    private func buildScriptArguments(vendor: ProjectVendor) -> [String] {
        var args: [String] = []
        switch vendor {
        case .stm32:
            if !settingsStore.armGccPath.isEmpty {
                args += ["--gcc", settingsStore.armGccPath]
            }
            if !settingsStore.openocdPath.isEmpty {
                args += ["--openocd", settingsStore.openocdPath]
            }
            if !settingsStore.openocdSpeed.isEmpty && settingsStore.openocdSpeed != "4000" {
                args += ["--adapter-speed", settingsStore.openocdSpeed]
            }
            if !settingsStore.stm32FlashSize.isEmpty {
                args += ["--flash-size", settingsStore.stm32FlashSize]
            }
            if !settingsStore.stm32RamSize.isEmpty {
                args += ["--ram-size", settingsStore.stm32RamSize]
            }
        case .tiMSPM0:
            if !settingsStore.tiArmClangPath.isEmpty {
                args += ["--cgt-root", settingsStore.tiArmClangPath]
            }
            if !settingsStore.mspm0SDKPath.isEmpty {
                args += ["--sdk-root", settingsStore.mspm0SDKPath]
            }
            if !settingsStore.jlinkPath.isEmpty {
                args += ["--jlink", settingsStore.jlinkPath]
            }
            if !settingsStore.jlinkSpeed.isEmpty && settingsStore.jlinkSpeed != "4000" {
                args += ["--speed", settingsStore.jlinkSpeed]
            }
        case .unknown:
            break
        }
        return args
    }

    func cancelTask() {
        scriptRunner.cancel()
        if runState.inProgress {
            runState = .cancelled
            log("[已取消] 用户已取消操作。")
        }
    }

    // MARK: - Utilities

    func openReport() {
        guard let project = currentProject else { return }
        _ = reportStore.openReport(for: project.rootURL, vendor: project.vendor)
    }

    func openArtifacts() {
        guard let project = currentProject else { return }
        if !reportStore.openBuildArtifact(for: project.rootURL, vendor: project.vendor) {
            _ = reportStore.openCodexBuild(for: project.rootURL)
        }
    }

    func copyDiagnostics() {
        let text = diagnostics.map { "• \($0.title): \($0.detail)\n  建议：\($0.suggestion)" }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? "无诊断信息。" : text, forType: .string)
    }

    func clearLogs() {
        logFlushTask?.cancel()
        logFlushTask = nil
        logBuffer = ""
        logs = []
        diagnostics = []
        buildProgress = 0
        if !runState.inProgress {
            runState = .idle
            if FloatingBallManager.shared.isBallMode {
                FloatingBallManager.shared.updateStatus(.idle)
            }
        }
    }

    func selectProjectByURL(_ url: URL) {
        scriptRunner.cancel()
        clearLogs()
        runState = .detecting

        let info = detector.detectProject(at: url)
        currentProject = info
        if settingsStore.saveRecentProjects {
            recentProjectStore.add(info)
        }

        startWatching(url)

        if info.vendor != .unknown {
            runState = .idle
        } else {
            runState = .failed("无法检测项目类型")
        }
    }

    /// 监听项目目录变动，AI/外部工具修改文件后自动刷新项目信息
    private func startWatching(_ url: URL) {
        projectWatcher?.cancel()
        projectWatcher = nil

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: projectWatcherQueue
        )
        var debounceWork: DispatchWorkItem?
        source.setEventHandler { [weak self] in
            debounceWork?.cancel()
            let work = DispatchWorkItem {
                DispatchQueue.main.async {
                    guard let self, let proj = self.currentProject else { return }
                    let fresh = self.detector.detectProject(at: proj.rootURL)
                    if fresh != proj {
                        self.currentProject = fresh
                        if self.settingsStore.saveRecentProjects {
                            self.recentProjectStore.add(fresh)
                        }
                    }
                }
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        projectWatcher = source
    }

    func openSettings() {
        showSettings = true
    }

    /// 追加日志（节流：缓冲后批量刷新，最多保留 maxLogEntries 条）
    private func log(_ text: String) {
        logBuffer += text + "\n"
        guard logFlushTask == nil else { return }
        logFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run {
                guard let self else { return }
                let buf = self.logBuffer
                guard !buf.isEmpty else { return }
                self.logs.append(LogEntry(text: buf))
                self.logBuffer = ""
                if self.logs.count > self.maxLogEntries {
                    self.logs.removeFirst(self.logs.count - self.maxLogEntries)
                }
                self.logFlushTask = nil
            }
        }
    }

    private func logDependencyResults(info: ToolchainInfo, vendor: ProjectVendor) {
        if vendor == .stm32 || vendor == .unknown {
            log(info.hasArmGCC ? "[环境检查] ARM GCC：\(info.armGcc!.path)" : "[环境检查] ARM GCC：未找到")
            log(info.hasOpenOCD ? "[环境检查] OpenOCD：\(info.openocd!.path)" : "[环境检查] OpenOCD：未找到")
            log(info.stlinkConnected ? "[环境检查] ST-Link：已连接 (USB)" : "[环境检查] ST-Link：未检测到")
        }
        if vendor == .tiMSPM0 || vendor == .unknown {
            log(info.hasTIArmClang ? "[环境检查] TI Arm Clang：\(info.tiArmClang!.path)" : "[环境检查] TI Arm Clang：未找到")
            log(info.hasMSPM0SDK ? "[环境检查] MSPM0 SDK：\(info.mspm0SDK!.path)" : "[环境检查] MSPM0 SDK：未找到")
            log(info.hasJLink ? "[环境检查] JLinkExe：\(info.jlinkExe!.path)" : "[环境检查] JLinkExe：未找到")
            log(info.jlinkConnected ? "[环境检查] J-Link：已检测到 (USB)" : "[环境检查] J-Link：未检测到")
        }
    }

    private func buildDependencyList(info: ToolchainInfo, vendor: ProjectVendor) -> [DependencyCheck] {
        var deps: [DependencyCheck] = []
        if vendor == .stm32 || vendor == .unknown {
            deps.append(DependencyCheck(name: "ARM GCC", status: info.hasArmGCC ? .ok : .missing, path: info.armGcc, message: info.hasArmGCC ? info.armGcc!.path : "未找到"))
            deps.append(DependencyCheck(name: "ARM Objcopy", status: info.armObjcopy != nil ? .ok : .missing, path: info.armObjcopy, message: info.armObjcopy?.path ?? "未找到"))
            deps.append(DependencyCheck(name: "ARM Size", status: info.armSize != nil ? .ok : .missing, path: info.armSize, message: info.armSize?.path ?? "未找到"))
            deps.append(DependencyCheck(name: "OpenOCD", status: info.hasOpenOCD ? .ok : .missing, path: info.openocd, message: info.hasOpenOCD ? info.openocd!.path : "未找到"))
            deps.append(DependencyCheck(name: "ST-Link (USB)", status: info.stlinkConnected ? .ok : .warning, message: info.stlinkConnected ? "已连接" : "未检测到"))
        }
        if vendor == .tiMSPM0 || vendor == .unknown {
            deps.append(DependencyCheck(name: "TI Arm Clang", status: info.hasTIArmClang ? .ok : .missing, path: info.tiArmClang, message: info.hasTIArmClang ? info.tiArmClang!.path : "未找到"))
            deps.append(DependencyCheck(name: "TI Objcopy", status: info.tiObjcopy != nil ? .ok : .missing, path: info.tiObjcopy, message: info.tiObjcopy?.path ?? "未找到"))
            deps.append(DependencyCheck(name: "MSPM0 SDK", status: info.hasMSPM0SDK ? .ok : .missing, path: info.mspm0SDK, message: info.hasMSPM0SDK ? info.mspm0SDK!.path : "未找到"))
            deps.append(DependencyCheck(name: "JLinkExe", status: info.hasJLink ? .ok : .missing, path: info.jlinkExe, message: info.hasJLink ? info.jlinkExe!.path : "未找到"))
            deps.append(DependencyCheck(name: "J-Link (USB)", status: info.jlinkConnected ? .ok : .warning, message: info.jlinkConnected ? "已检测到" : "未检测到"))
        }
        return deps
    }

    /// 直接在 setter 中同步悬浮球状态 — 与 runState 变更零延迟
    private func syncBallStatus(_ state: RunState) {
        print("[syncBallStatus] isBallMode=\(FloatingBallManager.shared.isBallMode) state=\(state)")
        guard FloatingBallManager.shared.isBallMode else { return }
        print("[syncBallStatus] calling updateStatus for \(state)")
        switch state {
        case .idle, .detecting, .checkingEnvironment:
            FloatingBallManager.shared.updateStatus(.idle)
        case .building:
            FloatingBallManager.shared.updateStatus(.building)
        case .flashing:
            FloatingBallManager.shared.updateStatus(.flashing)
        case .verifying:
            FloatingBallManager.shared.updateStatus(.verifying)
        case .success:
            FloatingBallManager.shared.updateStatus(.success("操作成功"))
        case .failed:
            FloatingBallManager.shared.updateStatus(.failure("操作失败"))
        case .cancelled:
            FloatingBallManager.shared.updateStatus(.idle)
        }
    }
}
