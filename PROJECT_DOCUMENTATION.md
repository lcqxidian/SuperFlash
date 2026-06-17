# SuperFlash — 完整工程文档

## 目录

1. [项目概述](#1-项目概述)
2. [项目结构](#2-项目结构)
3. [构建与部署](#3-构建与部署)
4. [依赖与工具链](#4-依赖与工具链)
5. [Package.swift](#5-packageswift)
6. [模型层 (Models)](#6-模型层-models)
7. [服务层 (Services)](#7-服务层-services)
8. [应用状态 (App/AppState)](#8-应用状态-appappstate)
9. [UI 层 (Views)](#9-ui-层-views)
10. [Python 烧录脚本](#10-python-烧录脚本)
11. [悬浮球系统](#11-悬浮球系统)
12. [中文本地化](#12-中文本地化)
13. [性能优化](#13-性能优化)
14. [开发历史与修改记录](#14-开发历史与修改记录)
15. [常见问题与边界情况](#15-常见问题与边界情况)

---

## 1. 项目概述

### 1.1 基本信息

- **项目名称**: SuperFlash
- **项目类型**: macOS 原生 SwiftUI 桌面应用
- **平台要求**: macOS 14.0+
- **架构**: ARM64 (Apple Silicon)
- **构建工具**: Swift Package Manager (Swift 6.0)
- **Bundle ID**: `com.lcq.SuperFlash`
- **版本**: 1.0.0

### 1.2 功能定位

SuperFlash 是一款一键嵌入式项目编译与烧录工具，支持以下 MCU 系列：

- **STM32F1/F4** — 使用 ARM GCC 编译，OpenOCD + ST-Link 烧录
- **TI MSPM0** — 使用 TI Arm Clang 编译，J-Link SWD 或 XDS110 烧录

### 1.3 核心工作流

```
选择项目目录 → 自动检测项目类型 → 检查工具链环境 → 编译 → 烧录 → 验证
```

所有步骤均可单独执行，也支持"编译并烧录"一键完成。

### 1.4 技术栈

- **前端**: SwiftUI (macOS 14+)，AppKit 桥接 (NSWindow, NSPopover, NSTextView, NSHostingView)
- **后端**: Swift 并发 (async/await, @MainActor, Combine)
- **编译脚本**: Python 3 (通过 Process/Pipe 调用)
- **持久化**: UserDefaults (JSON 序列化)
- **包管理**: Swift Package Manager (无第三方依赖)

---

## 2. 项目结构

```
SuperFlash/
├── Package.swift                              # SPM 包定义
├── PROJECT_DOCUMENTATION.md                   # 本文件
├── Sources/
│   └── SuperFlash/
│       ├── SuperFlashApp.swift                # @main 入口
│       ├── Resources/
│       │   └── scripts/
│       │       ├── stm32_build_flash.py        # STM32 编译烧录脚本
│       │       └── ti_mspm0_build_flash.py     # TI MSPM0 编译烧录脚本
│       ├── App/
│       │   └── AppState.swift                  # 全局应用状态 + 业务逻辑编排
│       ├── Models/
│       │   ├── BuildAction.swift               # 编译动作枚举
│       │   ├── DependencyCheck.swift           # 依赖检查模型
│       │   ├── DiagnosticIssue.swift           # 诊断信息模型
│       │   ├── LogEntry.swift                  # 日志条目模型
│       │   ├── ProjectInfo.swift               # 项目信息模型
│       │   ├── ProjectKind.swift               # 项目种类枚举
│       │   ├── ProjectVendor.swift             # 供应商枚举
│       │   ├── RunState.swift                  # 运行状态枚举
│       │   ├── STM32Family.swift               # STM32 系列枚举
│       │   └── ToolchainInfo.swift             # 工具链信息模型
│       ├── Services/
│       │   ├── BuildPlanGenerator.swift        # 编译方案生成器
│       │   ├── EnvironmentChecker.swift        # 环境检查 Actor
│       │   ├── LogParser.swift                 # 日志解析器
│       │   ├── ProjectDetector.swift           # 项目检测器
│       │   ├── RecentProjectStore.swift        # 最近项目存储
│       │   ├── ReportStore.swift               # 报告存储/打开
│       │   ├── ScriptRunner.swift              # 脚本运行器 (Process)
│       │   └── SettingsStore.swift             # 设置持久化存储
│       └── UI/
│           ├── ActionBarView.swift             # (已弃用) 旧版操作栏
│           ├── ContentView.swift               # 主界面布局
│           ├── DiagnosticView.swift            # 诊断信息面板
│           ├── EnvironmentCheckView.swift       # 环境检查面板
│           ├── FloatingBallManager.swift        # 悬浮球管理器 + 内容视图
│           ├── LogConsoleView.swift            # 编译输出控制台
│           ├── LogTextView.swift               # NSTextView 包装
│           ├── ProjectListView.swift           # 最近项目列表
│           ├── ProjectSummaryView.swift        # 项目摘要卡片
│           ├── SettingsView.swift              # 设置面板
│           └── StatusBannerView.swift          # 状态横幅
```

---

## 3. 构建与部署

### 3.1 开发构建

```bash
cd /Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash
swift build                    # Debug 构建
swift build -c release         # Release 构建
swift run SuperFlash           # 直接运行
```

### 3.2 部署到 /Applications

```bash
# 构建 release
swift build -c release

# 创建 .app 包
RELDIR=".build/arm64-apple-macosx/release"
BIN="$RELDIR/SuperFlash"
BUNDLE="$RELDIR/SuperFlash_SuperFlash.bundle"
APP="/Applications/SuperFlash.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/scripts"
cp "$BIN" "$APP/Contents/MacOS/SuperFlash"
cp "$BUNDLE/scripts/stm32_build_flash.py" "$APP/Contents/Resources/scripts/"
cp "$BUNDLE/scripts/ti_mspm0_build_flash.py" "$APP/Contents/Resources/scripts/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# 创建 Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string SuperFlash" \
  -c "Add :CFBundleExecutable string SuperFlash" \
  -c "Add :CFBundleIdentifier string com.lcq.SuperFlash" \
  -c "Add :CFBundleName string SuperFlash" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleShortVersionString string 1.0.0" \
  -c "Add :CFBundleVersion string 1" \
  -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" \
  -c "Add :LSMinimumSystemVersion string 14.0" \
  -c "Add :NSHighResolutionCapable bool true" \
  "$APP/Contents/Info.plist"

# Ad-hoc 签名
codesign --force --sign - "$APP"
```

### 3.3 签名说明

使用 ad-hoc 签名（`--sign -`），不需要 Apple Developer 账号。应用只能在当前设备运行。

---

## 4. 依赖与工具链

### 4.1 STM32 工具链

| 工具 | 用途 | 检测路径 |
|------|------|----------|
| `arm-none-eabi-gcc` | ARM GCC 编译器 | Homebrew, ARM 官方工具链, PATH |
| `arm-none-eabi-objcopy` | 二进制转换 | GCC 同级目录 |
| `arm-none-eabi-size` | 尺寸分析 | GCC 同级目录 |
| `openocd` | 烧录/调试 | Homebrew, PATH |
| ST-Link (USB) | 调试探针 | 通过 ioreg 检测 USB 设备 |

**重要**: ARM GCC 必须包含 newlib（支持 `#include <stdint.h>`）。Homebrew 版本 `arm-none-eabi-gcc` 在 16.1.0 之后可能缺少 newlib。脚本会自动检测并回退到 ARM 官方工具链 (`~/arm-gcc-toolchain/bin/`)。如果都缺少 newlib，脚本会在项目 `codex_build/` 目录生成最小 `stdint.h`。

### 4.2 TI MSPM0 工具链

| 工具 | 用途 | 检测路径 |
|------|------|----------|
| `tiarmclang` | TI Arm Clang 编译器 | `/Applications/ti/ccstheia*/ccs/tools/compiler/ti-cgt-armllvm_*/` |
| `tiarmobjcopy` | 二进制转换 | 编译器同级目录 |
| `tiarmsize` | 尺寸分析 | 编译器同级目录 |
| `JLinkExe` | J-Link 烧录 | `~/SEGGER_JLink_V950/`, `/Applications/SEGGER/`, PATH |
| `DSLite` | XDS110 烧录 (备用) | TI CCS 安装目录 |
| MSPM0 SDK | 芯片支持包 | `/Applications/ti/mspm0_sdk_*/` |

### 4.3 环境变量覆盖

设置面板中可以自定义工具路径，设置保存在 UserDefaults 中，通过 `--gcc`、`--openocd`、`--cgt-root`、`--sdk-root`、`--jlink`、`--speed` 等 CLI 参数传递给 Python 脚本。

---

## 5. Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperFlash",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SuperFlash",
            resources: [.copy("Resources/scripts")]
        )
    ]
)
```

关键点：
- `swift-tools-version: 6.0` — 启用 Swift 6 严格并发检查
- `.macOS(.v14)` — 最低系统版本 macOS Sonoma
- 资源通过 `.copy("Resources/scripts")` 打包，在 bundle 中位于 `scripts/` 子目录
- 无第三方依赖

---

## 6. 模型层 (Models)

### 6.1 ProjectVendor (ProjectVendor.swift)

```swift
enum ProjectVendor: String, Codable, CaseIterable {
    case stm32 = "STM32"
    case tiMSPM0 = "TI MSPM0"
    case unknown = "未知"
    
    var displayName: String {
        switch self {
        case .stm32: return "STM32"
        case .tiMSPM0: return "TI MSPM0"
        case .unknown: return "未知"
        }
    }
}
```

`rawValue` 用于日志标签（如 `[STM32]`），`displayName` 用于界面显示。

### 6.2 STM32Family (STM32Family.swift)

```swift
enum STM32Family: String, Codable {
    case f1, f4, unknown
    
    var cpuFlags: [String] {
        // f1: cortex-m3
        // f4: cortex-m4 + fpv4-sp-d16 + hard-float
    }
    
    var openOCDTarget: String {
        // f1 → "target/stm32f1x.cfg"
        // f4 → "target/stm32f4x.cfg"
    }
}
```

Python 脚本中的 `stm32_build_flash.py` 有更完整的系列支持（F0/F1/F2/F3/F4/F7/H7/G0/G4/L0/L1/L4/U5），每种都有对应的 CPU flags。

### 6.3 ProjectKind (ProjectKind.swift)

```swift
enum ProjectKind: String, Codable {
    case keil = "Keil"
    case bareFolder = "裸文件夹"
    case makefile = "Makefile"
    case cubeIDE = "CubeIDE"
    case ccsSysConfig = "CCS/SysConfig"
    case unknown = "未知"
    
    var displayName: String { rawValue }
}
```

### 6.4 BuildAction (BuildAction.swift)

```swift
enum BuildAction: CaseIterable {
    case build           // 仅编译
    case flash           // 仅烧录
    case buildAndFlash   // 编译并烧录
    case verify          // 验证连接
    
    var cliValue: String        // build / flash / all / verify
    var displayName: String     // 编译 / 烧录 / 编译并烧录 / 验证连接
}
```

### 6.5 RunState (RunState.swift)

```swift
enum RunState: Equatable {
    case idle
    case detecting
    case checkingEnvironment
    case building
    case flashing
    case verifying
    case success
    case failed(String)
    case cancelled
    
    var inProgress: Bool {
        switch self {
        case .detecting, .checkingEnvironment, .building, .flashing, .verifying:
            return true
        default: return false
        }
    }
    
    var displayName: String {
        // idle→就绪, detecting→检测中, building→编译中, success→成功, 等
    }
}
```

### 6.6 ProjectInfo (ProjectInfo.swift)

核心模型，包含项目的所有元数据：

```swift
struct ProjectInfo: Codable, Identifiable, Equatable {
    var id: UUID
    var rootURL: URL               // 项目根目录
    var displayName: String         // 显示名称
    var vendor: ProjectVendor       // 供应商
    var projectKind: ProjectKind    // 项目种类
    var chipName: String?           // 芯片型号
    var stm32Family: STM32Family?   // STM32 系列
    
    // 检测到的文件
    var makefile: URL?
    var keilProject: URL?
    var iocFile: URL?
    var startupFile: URL?
    var linkerScript: URL?
    var syscfgFile: URL?
    var tiConfigFile: URL?
    var tiLinkerCmd: URL?
    
    var mainFiles: [URL]
    var sourceCount: Int            // C 源文件数
    var includeCount: Int           // 头文件数
    
    // 计算属性
    var isDetected: Bool            // vendor != .unknown
    var buildMethod: String         // "现有 Makefile" / "生成 GCC 编译" / "TI Arm Clang + SysConfig"
    var flashMethod: String         // "OpenOCD + ST-Link" / "J-Link SWD"
    var buildReady: Bool            // vendor != .unknown
}
```

### 6.7 ToolchainInfo (ToolchainInfo.swift)

```swift
struct ToolchainInfo {
    var armGcc: URL?
    var armObjcopy: URL?
    var armSize: URL?
    var openocd: URL?
    var tiArmClang: URL?
    var tiObjcopy: URL?
    var tiSize: URL?
    var mspm0SDK: URL?
    var jlinkExe: URL?
    
    // 计算属性 has*
    var hasArmGCC: Bool { armGcc != nil }
    var stlinkConnected: Bool       // 通过 ioreg 检测
    var jlinkConnected: Bool        // 通过 ioreg 检测
}
```

### 6.8 DependencyCheck (DependencyCheck.swift)

```swift
struct DependencyCheck: Identifiable {
    var id = UUID()
    var name: String                // 工具名称
    var status: DependencyStatus    // ok/warning/missing/unknown
    var path: URL?                  // 工具路径
    var message: String             // 状态描述
}

enum DependencyStatus: String, Codable {
    case ok, warning, missing, unknown
    
    var displayName: String {
        // ok→正常, warning→警告, missing→缺失, unknown→未知
    }
}
```

### 6.9 LogEntry (LogEntry.swift)

```swift
struct LogEntry: Identifiable {
    var id = UUID()
    let timestamp = Date()
    let text: String
}
```

### 6.10 DiagnosticIssue (DiagnosticIssue.swift)

```swift
struct DiagnosticIssue: Identifiable {
    var id = UUID()
    let title: String
    let detail: String
    let suggestion: String
}
```

所有 title/detail/suggestion 均已中文化。

---

## 7. 服务层 (Services)

### 7.1 AppState (App/AppState.swift)

虽然放在 App/ 目录，但本质上是核心编排器（Orchestrator），管理所有业务逻辑。

**`@Published` 属性:**

| 属性 | 类型 | 用途 |
|------|------|------|
| `currentProject` | `ProjectInfo?` | 当前选中的项目 |
| `toolchainInfo` | `ToolchainInfo` | 工具链检测结果 |
| `dependencies` | `[DependencyCheck]` | 依赖检查列表 |
| `diagnostics` | `[DiagnosticIssue]` | 诊断信息列表 |
| `runState` | `RunState` | 当前运行状态 |
| `logs` | `[LogEntry]` | 日志条目 |
| `showSettings` | `Bool` | 设置面板开关 |
| `buildProgress` | `Double` | 实时编译进度 (0~1) |

**常规模块:**

```swift
let detector = ProjectDetector()
let environmentChecker = EnvironmentChecker()   // Actor
let logParser = LogParser()
let reportStore = ReportStore()
let planGenerator = BuildPlanGenerator()
let settingsStore = SettingsStore()
let recentProjectStore = RecentProjectStore()
private let scriptRunner = ScriptRunner()
```

**Computed 属性:**

```swift
var allLogText: String { logs.map(\.text).joined() }
```

**核心方法:**

| 方法 | 功能 |
|------|------|
| `selectProject()` | 打开 NSOpenPanel 选择目录，检测项目 |
| `redetectCurrentProject()` | 重新检测当前项目 |
| `selectProjectByURL(_:)` | 通过 URL 选择项目（用于最近项目列表） |
| `checkEnvironment()` | 在 Task 中异步检查工具链 |
| `runAction(_:)` | 执行编译/烧录/验证操作 |
| `cancelTask()` | 取消当前操作 |
| `openReport()` | 打开编译报告 |
| `openArtifacts()` | 打开编译产物目录 |
| `copyDiagnostics()` | 复制诊断信息到剪贴板 |
| `clearLogs()` | 清除日志和诊断 |

**runAction 详细流程:**

1. 校验：项目存在、供应商已知、有对应的 Python 脚本
2. 重置日志和诊断（不经过 `.idle` 状态，避免 UI 闪烁）
3. 直接更新悬浮球状态（同步，不依赖 `.onChange`）
4. 设置 `runState` 为对应操作状态
5. 构建脚本参数（来自设置面板的自定义路径）
6. 设置 `outputHandler`：接收 Python 脚本的 stdout
7. 设置 `completionHandler`：处理退出码 + 日志解析
8. 调用 `scriptRunner.run()` 启动子进程

**进度追踪机制:**

```
在 outputHandler 中：
  1. 累积输出到 progressAccumulated
  2. 统计每行包含 " $" 的命令行数量（表示一条编译命令完成）
  3. 减去上一次统计数得到新增完成数
  4. buildProgress += 新增数 / 总步数
  5. 总步数 = sourceCount + 5（源码 + startup + 链接 + objcopy×2 + size）

在 completionHandler 中：
  buildProgress = 1.0（完成时强制设为完整进度）
```

### 7.2 ScriptRunner (ScriptRunner.swift)

线程安全的子进程管理器，使用 `Process` + `Pipe` 实现：

```swift
final class ScriptRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _outputHandler: OutputHandler?
    private var _completionHandler: CompletionHandler?
    private let _accumulated = MutableBox("")
    
    typealias OutputHandler = @Sendable (String) -> Void
    typealias CompletionHandler = @Sendable (Int32, String) -> Void
}
```

**关键实现细节:**

- `run()` 方法：
  1. `cancel()` 终止之前的进程
  2. 创建 `Process`，设置 `/usr/bin/python3` 作为可执行文件
  3. 参数：脚本路径、项目路径、`--action`、自定义参数
  4. 设置环境变量 PATH（含 Homebrew 路径）+ 自定义覆盖
  5. 合并 stdout/stderr 到同一个 Pipe
  6. `readabilityHandler` 实时读取输出，通过 `MutableBox` 线程安全地交给 `outputHandler`
  7. `terminationHandler` 在进程结束时调用 `completionHandler`

- `cancel()` 方法：终止进程并清理

- `MutableBox<T>`：`@unchecked Sendable` 的引用类型包装器，解决 Swift 6 严格并发下闭包捕获问题

**环境变量 PATH 设置:**

```swift
let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
env["PATH"] = (env["PATH"] != nil) ? "\(defaultPATH):\(env["PATH"]!)" : defaultPATH
```

### 7.3 EnvironmentChecker (EnvironmentChecker.swift)

`actor` 实现，所有方法在 actor 隔离中安全执行：

```swift
actor EnvironmentChecker {
    func checkAll(
        armGccOverride: String = "",
        openocdOverride: String = "",
        tiArmClangOverride: String = "",
        mspm0SDKOverride: String = "",
        jlinkOverride: String = ""
    ) -> ToolchainInfo
}
```

**检测逻辑:**

1. 先检查用户自定义覆盖路径（通过设置面板传入）
2. 自定义路径无效或不存在时，自动检测常用路径
3. `findExec(_:extraPaths:)` 搜索指定目录 + PATH
4. `whichShell(_:)` 通过 `which` 命令搜索
5. 硬件检测通过 `ioreg -p IOUSB -l -w0` 搜索 USB 设备

**ST-Link 检测:**

```swift
private func detectSTLink() -> Bool {
    // 运行 ioreg 搜索 "ST-LINK", "STLink", "STMicroelectronics"
}
```

**J-Link 检测:**

```swift
private func detectJLink() -> Bool {
    // 运行 ioreg 搜索 "J-Link", "SEGGER"
}
```

**TI Arm Clang 查找:**

```swift
private func findTIArmClang() -> URL? {
    // 搜索 /Applications/ti/ccstheia*/ 和 /Applications/ti/ccs*/
    // 查找 ti-cgt-armllvm_*/bin/tiarmclang
}
```

### 7.4 ProjectDetector (ProjectDetector.swift)

基于评分系统的项目类型自动检测：

```swift
func detectProject(at url: URL) -> ProjectInfo
```

**STM32 评分规则:**

| 文件/特征 | 分数 |
|-----------|------|
| `*.ioc` (CubeMX 配置) | +5 |
| `*.uvprojx` (Keil 项目) | +4 |
| `startup_stm32*.s` (启动文件) | +4 |
| `STM32*.ld` (链接脚本) | +3 |
| `stm32*.h` (头文件) | +2 |
| `Makefile` | +1 |
| `main.c` | +1 |

**TI MSPM0 评分规则:**

| 文件/特征 | 分数 |
|-----------|------|
| `targetConfigs/*.ccxml` | +5 |
| `ti_msp_dl_config.c` | +4 |
| `*.syscfg` | +4 |
| `device_linker.cmd` | +3 |
| `.ccsproject` / `.cproject` | +2 |
| 项目名包含 "MSPM0" | +2 |
| `Makefile` | +1 |

**通配符匹配:**

```swift
private func wildcardMatch(_ value: String, pattern: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: pattern)
        .replacingOccurrences(of: "\\*", with: ".*")
    return value.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
}
```

### 7.5 LogParser (LogParser.swift)

日志解析器，负责两件事：

**1. 诊断提取 (`parseDiagnostics`):**

按优先级检查以下失败模式：

| 关键词 | 诊断标题 |
|--------|----------|
| `arm-none-eabi-gcc: command not found` | 未找到 ARM GCC |
| `openocd: command not found` | 未找到 OpenOCD |
| `unsupported j-link probe` / `sam-ice` | 当前 J-Link 不支持 TI MSPM0 |
| `failed to initialize dap` | J-Link DAP 初始化失败 |
| `could not connect to the target device` | 无法连接到目标 |
| `target not examined` / `no device` | 未检测到 ST-Link/目标 |
| `verification failed` / `verify failed` | 烧录验证失败 |
| `no such file` / `not found` | 文件未找到 |
| `command not found` / `not a valid command` | 缺少工具 |
| fallback (且 `succeeded=false`) | 未知错误 |

**2. 成功判定 (`checkSuccess`):**

先检查失败关键词，有则返回 false。再根据动作类型检查成功关键词：

| 动作 | 成功信号 |
|------|----------|
| build | linking / completed / success / nothing to be done / report written / arm-none-eabi-size / tiarmsize / tiarmobjcopy |
| flash | verified / O.K. |
| verify | ipsr = 000 / target halted / O.K. |
| buildAndFlash | (build 成功) AND (flash 成功) |

### 7.6 BuildPlanGenerator (BuildPlanGenerator.swift)

供应商 → 脚本名映射：

```swift
func selectScript(for vendor: ProjectVendor) -> String? {
    switch vendor {
    case .stm32: return "stm32_build_flash"
    case .tiMSPM0: return "ti_mspm0_build_flash"
    case .unknown: return nil
    }
}
```

### 7.7 SettingsStore (SettingsStore.swift)

UserDefaults 持久化，JSON 序列化：

```swift
final class SettingsStore: ObservableObject {
    @Published var armGccPath: String = ""
    @Published var openocdPath: String = ""
    @Published var tiArmClangPath: String = ""
    @Published var mspm0SDKPath: String = ""
    @Published var jlinkPath: String = ""
    @Published var openocdSpeed: String = "4000"
    @Published var jlinkSpeed: String = "4000"
    @Published var saveRecentProjects: Bool = true
    
    var envOverrides: [String: String] {
        // 生成环境变量字典传给脚本
    }
}
```

### 7.8 RecentProjectStore (RecentProjectStore.swift)

```swift
final class RecentProjectStore: ObservableObject {
    @Published var recentProjects: [ProjectInfo] = []
    
    func add(_:)   // 去重插入到首位，最多 10 个
    func remove(_:) // 按 id 移除
    func clear()    // 清空
}
```

### 7.9 ReportStore (ReportStore.swift)

通过 `NSWorkspace.shared.open()` 打开文件/目录：

```swift
func openReport(for url: URL, vendor: ProjectVendor) -> Bool
func openBuildArtifact(for url: URL, vendor: ProjectVendor) -> Bool
func openCodexBuild(for url: URL) -> Bool
```

---

## 8. 应用状态 (App/AppState)

### 8.1 日志节流机制

为避免大量编译输出触发过多的 UI 刷新，实现了日志节流：

```swift
private var logBuffer = ""
private var logFlushTask: Task<Void, Never>?

private func log(_ text: String) {
    logBuffer += text + "\n"
    guard logFlushTask == nil else { return }
    logFlushTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms 批量窗口
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
```

- 缓冲 80ms，期间所有日志合并为一条 LogEntry
- 最多保留 500 条日志
- 使用 `Task { try? await Task.sleep }` 实现非阻塞延迟

### 8.2 进度追踪

```swift
@Published var buildProgress: Double = 0
private var progressAccumulated = ""
private var progressLastCmdCount = 0
private var progressTotalSteps: Double = 20

// 初始化（在 runAction 中）：
let srcCount = max(project.sourceCount, 1)
progressTotalSteps = Double(srcCount + 5)  // 源码 + startup + 链接 + objcopy×2 + size
buildProgress = 0
progressAccumulated = ""
progressLastCmdCount = 0

// 在 outputHandler 中统计：
progressAccumulated += text
let cmdCount = progressAccumulated.components(separatedBy: "\n")
    .filter { $0.contains(" $ ") }.count
let newCmds = cmdCount - progressLastCmdCount
if newCmds > 0 {
    progressLastCmdCount = cmdCount
    buildProgress = min(0.95, buildProgress + Double(newCmds) / progressTotalSteps)
}

// 在 completionHandler 中：
buildProgress = 1  // 完成时设为完整
```

### 8.3 悬浮球状态同步

AppState 直接同步悬浮球状态（不依赖 `.onChange`，避免竞态）：

```swift
// runAction 中：
let ballStatus: BallStatus
switch action {
case .build: ballStatus = .building; runState = .building
case .flash: ballStatus = .flashing; runState = .flashing
// ...
}
if ball.isBallMode { ball.updateStatus(ballStatus) }

// completionHandler 中：
if FloatingBallManager.shared.isBallMode {
    FloatingBallManager.shared.updateStatus(.success("操作成功"))
    // 或 .failure("操作失败")
}
```

### 8.4 脚本参数构建

```swift
private func buildScriptArguments(vendor: ProjectVendor) -> [String] {
    var args: [String] = []
    switch vendor {
    case .stm32:
        if !settingsStore.armGccPath.isEmpty { args += ["--gcc", settingsStore.armGccPath] }
        if !settingsStore.openocdPath.isEmpty { args += ["--openocd", settingsStore.openocdPath] }
        if !settingsStore.openocdSpeed.isEmpty && settingsStore.openocdSpeed != "4000" {
            args += ["--adapter-speed", settingsStore.openocdSpeed]
        }
    case .tiMSPM0:
        if !settingsStore.tiArmClangPath.isEmpty { args += ["--cgt-root", settingsStore.tiArmClangPath] }
        if !settingsStore.mspm0SDKPath.isEmpty { args += ["--sdk-root", settingsStore.mspm0SDKPath] }
        if !settingsStore.jlinkPath.isEmpty { args += ["--jlink", settingsStore.jlinkPath] }
        if !settingsStore.jlinkSpeed.isEmpty && settingsStore.jlinkSpeed != "4000" {
            args += ["--speed", settingsStore.jlinkSpeed]
        }
    case .unknown: break
    }
    return args
}
```

### 8.5 脚本资源查找

```swift
private func bundledScriptURL(scriptName: String) -> URL? {
    // 1. 优先查找 Bundle.main 中的 scripts/ 目录
    if let appResourceURL = Bundle.main.resourceURL?
        .appendingPathComponent("scripts")
        .appendingPathComponent("\(scriptName).py"),
       FileManager.default.fileExists(atPath: appResourceURL.path) {
        return appResourceURL
    }
    // 2. 回退到 SwiftPM Bundle.module
    return Bundle.module.url(
        forResource: scriptName,
        withExtension: "py",
        subdirectory: "scripts"
    )
}
```

---

## 9. UI 层 (Views)

### 9.1 三栏布局 (ContentView.swift)

```
┌──────────────────┬───────────────────────┬──────────────────┐
│   左栏 200-300px │   中栏 360-480px      │   右栏 300-480px │
│                  │                       │                  │
│   最近项目列表   │   状态横幅             │   编译输出控制台  │
│   ─────────     │   (操作中/完成/失败)   │   (NSTextView)   │
│   · 项目 1      │                       │                  │
│   · 项目 2      │   项目信息卡片          │                  │
│   · 项目 3      │                       │                  │
│                  │   操作按钮面板          │                  │
│                  │   ┌────┬────┬──────┐  │                  │
│                  │   │编译│烧录│编译并│  │                  │
│                  │   │    │    │烧录  │  │                  │
│                  │   └────┴────┴──────┘  │                  │
│                  │                       │                  │
│                  │   环境检查结果          │                  │
│                  │   诊断信息              │                  │
│                  │                       │                  │
└──────────────────┴───────────────────────┴──────────────────┘
```

**ContentView 结构:**

```swift
HSplitView {
    ProjectListView          // 左栏
    centerPanel              // 中栏 (VStack)
        StatusBannerView
        ScrollView
            ProjectSummaryView
            actionButtonPanel
            EnvironmentCheckView
            DiagnosticView
    LogConsoleView           // 右栏
}
```

**界面右上角悬浮球按钮:**

```swift
.overlay(alignment: .topTrailing) {
    Button { FloatingBallManager.shared.toggle() } label: {
        Image(systemName: "circle.fill")
            .font(.system(size: 14))
            .foregroundColor(.accentColor)
            .background(Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 28, height: 28))
    }
    .buttonStyle(.plain)
    .help("切换悬浮球 (⇧⌘M)")
    .padding(6)
}
```

**状态同步 (.onChange 链):**

```swift
// 同步 runState → BallStatus
.onChange(of: appState.runState) { _, newState in
    let ball = FloatingBallManager.shared
    switch newState {
    case .idle, .detecting, .checkingEnvironment:
        if ball.isBallMode { ball.updateStatus(.idle) }
    case .building:   if ball.isBallMode { ball.updateStatus(.building) }
    case .flashing:   if ball.isBallMode { ball.updateStatus(.flashing) }
    case .verifying:  if ball.isBallMode { ball.updateStatus(.verifying) }
    case .success:    if ball.isBallMode { ball.updateStatus(.success("操作成功")) }
    case .failed:     if ball.isBallMode { ball.updateStatus(.failure("操作失败")) }
    case .cancelled:  if ball.isBallMode { ball.updateStatus(.idle) }
    }
}

// 同步 buildProgress → FloatingBallManager
.onChange(of: appState.buildProgress) { _, progress in
    guard FloatingBallManager.shared.isBallMode else { return }
    FloatingBallManager.shared.buildProgress = progress
}
```

### 9.2 Compose 子组件

**ToolbarActionButton** — 工具栏图标按钮（只显示 SF Symbol，hover 高亮）：

```swift
struct ToolbarActionButton: View {
    let title: String, icon: String, action: () -> Void
    @State private var isHovered = false
    // .labelStyle(.iconOnly)
    // hover 时 accentColor 背景
}
```

**BuildActionButton** — 编译/烧录操作按钮（大尺寸，图标 + 文字竖排）：

```swift
struct BuildActionButton: View {
    let title: String, icon: String, action: () -> Void
    var disabled: Bool = false, prominent: Bool = false
    // prominent 时用 .borderedProminent，否则 .bordered
    // 操作中 disabled + 半透明
}
```

**CancelButton** — 取消按钮（红色 + ProgressView spinner）：

```swift
struct CancelButton: View {
    let action: () -> Void
    // 红色 .borderedProminent + ProgressView
}
```

**ToolButton** — 小型工具按钮（纯图标，hover accent）：

```swift
struct ToolButton: View {
    let icon: String, title: String, action: () -> Void
    // .borderless, hover accent
}
```

### 9.3 ProjectListView (左栏)

**空状态:** 大图标 + "暂无最近项目" + "点击「选择项目」开始"

**项目行 (ProjectRow):**

```swift
ZStack(alignment: .trailing) {
    // 选择层（内容 HStack，onTapGesture 选择项目）
    HStack {
        vendorIcon (STM32蓝色/橙色)
        VStack { 项目名, 供应商名 }
        Spacer()
    }
    .contentShape(Rectangle())
    .onTapGesture { onSelect() }
    
    // 叉号按钮（hover 时显示）
    if isHovered {
        Button(action: onRemove) { Image(systemName: "xmark") }
            .buttonStyle(.borderless)
    }
}
```

使用 `ZStack` 分离选择点击和移除按钮，避免 `onTapGesture` 与 `Button` 的交互冲突。

### 9.4 ProjectSummaryView (项目信息卡片)

`GroupBox` 套用 `CardGroupBoxStyle`：

```
┌─────────────────────────────────────┐
│  项目名                 [STM32]     │
│  ─────────────────────────────────  │
│  🔧 种类      Makefile 项目         │
│  🔩 芯片      STM32F407ZG           │
│  🔨 编译方式  现有 Makefile          │
│  💾 烧录方式  OpenOCD + ST-Link     │
│  📄 源文件    12 个                  │
│  ✏️ 头文件    8 个                   │
│  ✅ 包含 Makefile                    │
└─────────────────────────────────────┘
```

**CardGroupBoxStyle:**

```swift
struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.content.padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}
```

### 9.5 StatusBannerView (状态横幅)

根据 `runState` 显示不同样式的横幅：

| 状态 | 样式 |
|------|------|
| `detecting` | 线性渐变背景 + ProgressView + "正在检测项目..." |
| `checkingEnvironment` | 同上 + "正在检查环境..." |
| `building` | 同上 + "正在编译..." |
| `flashing` | 同上 + "正在烧录..." |
| `verifying` | 同上 + "正在验证..." |
| `success` | 绿色背景 + checkmark + "操作成功完成！" |
| `failed(reason)` | 红色背景 + xmark + 失败原因 |
| `cancelled` | 橙色背景 + xmark + "操作已取消" |
| `idle` | EmptyView（不显示） |

### 9.6 EnvironmentCheckView (依赖检查)

```
┌─ 依赖检查 ──────────────────────────┐
│ ✅ ARM GCC         正常   /usr/bin/..│
│ ✅ OpenOCD         正常   /usr/bin/..│
│ ⚠️ ST-Link (USB)   警告   未检测到   │
│ ❌ TI Arm Clang    缺失   未找到     │
└──────────────────────────────────────┘
```

每个依赖项显示：状态图标 + 名称 + 路径 + 状态胶囊徽章

### 9.7 DiagnosticView (诊断信息)

```
┌─ 诊断信息 (2) ──────────────────────┐
│ ⚠ 未找到 ARM GCC                    │
│   在 PATH 中未找到 arm-none-eabi-gcc │
│   💡 通过 Homebrew 安装：brew install│
└──────────────────────────────────────┘
```

每个诊断项显示：标题 + 详情 + 建议（带灯泡图标）

### 9.8 LogConsoleView (右栏)

使用 **NSTextView** (通过 NSViewRepresentable 包装) 替代 SwiftUI Text：

```swift
struct LogTextView: NSViewRepresentable {
    let logs: [LogEntry]
    @Binding var autoScroll: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true      // 支持 Cmd+A 全选
        textView.font = .monospacedSystemFont(ofSize: 11)
        // ...
    }
    
    func updateNSView(...) {
        // 用 NSAttributedString 设置带颜色的文本
        // 日志无变化时跳过更新
        // 自动滚动到底部
    }
}
```

**NSTextView 优势:**
- 原生支持 Cmd+A 全选
- 支持任意范围拖选复制
- 对大量文本渲染性能优于 SwiftUI Text
- 日志缓冲 80ms 后批量更新

**颜色规则:**

| 关键词 | 颜色 |
|--------|------|
| error / fail / fatal | 红色 |
| warning | 橙色 |
| success / ok / verified / completed | 绿色 |
| [cancel / [已取消 | 橙色 |
| 其他 | primary |

### 9.9 SettingsView (设置面板)

TabView 双标签页：

**路径标签:** Form 表单
- STM32 工具链：ARM GCC 路径、OpenOCD 路径、OpenOCD 速度
- TI MSPM0 工具链：TI Arm Clang 根目录、MSPM0 SDK 根目录、JLinkExe 路径、J-Link 速度
- 行为设置：保存最近项目

**关于标签:** 版本信息 + 功能简介

### 9.10 ActionBarView (已弃用)

旧的单行操作栏，已被 ContentView 内联的 `actionButtonPanel` 替代。保留在项目中但不再使用。

---

## 10. Python 烧录脚本

### 10.1 stm32_build_flash.py

**位置:** `Sources/SuperFlash/Resources/scripts/stm32_build_flash.py`

**命令行参数:**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `project_dir` | positional | `.` | 项目目录 |
| `--action` | `build/flash/verify/all` | `all` | 操作类型 |
| `--mcu` | str | — | MCU 型号（如 STM32F407ZG） |
| `--target-cfg` | str | — | OpenOCD target 配置文件 |
| `--interface-cfg` | str | `interface/stlink.cfg` | OpenOCD interface 配置 |
| `--adapter-speed` | str | `4000` | OpenOCD 速度 (kHz) |
| `--project-name` | str | — | 输出文件名 |
| `--make-target` | str | — | Makefile 目标 |
| `--force-generated-build` | flag | false | 强制使用生成构建 |
| `--gcc` | str | — | arm-none-eabi-gcc 路径 |
| `--openocd` | str | — | openocd 路径 |

**工作流程:**

1. **查找 GCC:** `find_gcc(override)` → 验证 newlib 支持
2. **检测 MCU:** `detect_mcu(project, mcu)` → 从 .ioc/.ld/startup 等文件提取
3. **确定系列:** `family_from_mcu(mcu)` → cortex-m3/m4 等 CPU flags
4. **构建:**
   - 优先使用现有 Makefile（除非 `--force-generated-build`）
   - 无 Makefile 时生成 GCC 构建
5. **生成构建:** `build_generated()` → 逐文件编译 → 链接 → objcopy
6. **烧录:** `flash_with_openocd()` 或 `cube_flash()`
7. **验证:** `verify_with_openocd()`
8. **报告:** 写入 `codex_build/STM32_BUILD_FLASH_REPORT.md`

**关键函数:**

| 函数 | 功能 |
|------|------|
| `find_gcc()` | 查找并验证 ARM GCC（含 newlib） |
| `find_openocd()` | 查找 OpenOCD |
| `detect_mcu()` | 从项目文件自动检测 MCU 型号 |
| `family_from_mcu()` | MCU → 内核系列（含 CPU flags） |
| `detect_defines()` | 检测 HAL/StdPeriph 宏定义 |
| `generate_linker_script()` | 自动生成链接脚本 |
| `generate_startup_file()` | 自动转换 Keil 启动文件为 GCC 语法 |
| `discover_sources()` | 遍历项目源码文件 |
| `build_generated()` | 逐文件编译 + 链接 |
| `flash_with_openocd()` | OpenOCD 烧录 |
| `verify_with_openocd()` | OpenOCD 验证 |
| `cube_flash()` | STM32CubeProgrammer 烧录（备用） |

**newlib 验证:**

```python
def find_gcc(override=None):
    # ...
    # 编译 #include <stdint.h> 测试 newlib
    test = subprocess.run(
        [str(candidate), "-c", "-x", "c", "-", "-mcpu=cortex-m4", "-mthumb",
         "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard", "-o", "/dev/null"],
        input="#include <stdint.h>\n", text=True, capture_output=True, timeout=30
    )
    if test.returncode == 0: return candidate
    # 跳过缺少 newlib 的工具链
```

**MCU 内存表（用于生成链接脚本）:**

```python
memory_map = {
    "STM32F103C8":  (0x10000,  0x5000),    # 64KB + 20KB
    "STM32F407ZG":  (0x100000, 0x20000),   # 1MB + 128KB
    "STM32F429ZI":  (0x200000, 0x30000),   # 2MB + 192KB
    # ... 更多型号
}
```

### 10.2 ti_mspm0_build_flash.py

**位置:** `Sources/SuperFlash/Resources/scripts/ti_mspm0_build_flash.py`

**命令行参数:**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `project_dir` | positional | `.` | 项目目录 |
| `--action` | `build/flash/verify/all` | `all` | 操作类型 |
| `--device` | str | — | 设备型号（如 MSPM0G3507） |
| `--project-name` | str | — | 输出文件名 |
| `--sdk-root` | str | — | MSPM0 SDK 根目录 |
| `--cgt-root` | str | — | TI Arm Clang 根目录 |
| `--jlink` | str | — | JLinkExe 路径 |
| `--dslite` | str | — | DSLite 路径 |
| `--probe` | `auto/xds110/jlink` | `auto` | 调试探针选择 |
| `--speed` | str | `4000` | J-Link SWD 速度 (kHz) |

**烧录探针自动选择 (`choose_probe`):**

```
auto → 检测 XDS110 → 有: xds110
       └── 无 → 检测 DSLite → 有 → 检测 J-Link 类型
                                    ├── SAM-ICE/老 JLink ARM-OB → dslite_jlink
                                    └── 其他通用 J-Link → jlink
                         └── 无 → jlink（仅有 JLinkExe）
```

**fallback 链 (`flash_or_verify`):**

1. 优先使用所选探针
2. JLinkExe 失败时 → DSLite + J-Link ccxml 回退
3. DSLite 不可用 → 报错

**关键函数:**

| 函数 | 功能 |
|------|------|
| `normalize_cgt_root()` | 规范化 TI Arm Clang 路径 |
| `find_cgt_root()` | 查找 TI Arm Clang 编译器 |
| `find_sdk_root()` | 查找 MSPM0 SDK |
| `find_jlink()` | 查找 JLinkExe |
| `find_dslite()` | 查找 DSLite |
| `xds110_connected()` | 检测 XDS110 探针 |
| `detect_device()` | 从项目文件检测设备型号 |
| `build_project()` | 逐文件编译 + 链接 |
| `choose_probe()` | 自动选择烧录探针 |
| `flash_or_verify()` | 多路复用 + fallback 烧录/验证 |
| `jlink_output_succeeded()` | 通过输出文本判断 JLinkExe 结果 |
| `write_report()` | 生成报告（含中文交接提示） |

**J-Link output 成功判定:**

```python
def jlink_output_succeeded(kind, output):
    failure_patterns = [
        "Could not connect to the target device",
        "Failed to initialize DAP",
        "Target connection not established",
        "Connect failed",
        "returned with error code",
        "Can not attach to CPU",
        "Mass erase failed",
        "Factory reset failed",
        "Cannot connect",
        "Error occurred:",
        "****** Error:",
    ]
    if any(pattern in output for pattern in failure_patterns):
        return False
    if kind == "flash":
        return "O.K." in output
    if kind == "verify":
        return "IPSR = 000" in output and "(NoException)" in output
    return False
```

---

## 11. 悬浮球系统

### 11.1 整体架构

```
FloatingBallManager (ObservableObject, @MainActor, singleton)
├── @Published isBallMode: Bool        // 是否处于球模式
├── @Published status: BallStatus      // 球体状态
├── @Published buildProgress: Double   // 进度 (0~1)
├── onBuild / onBuildAndFlash / onVerify   // 回调
├── ballWindow: NSWindow?              // 球体窗口
├── mainWindow: NSWindow?              // 主窗口引用
│
└── FloatingBallContent (SwiftUI View)
    ├── 左侧：操作按钮（hover 淡入）
    └── 右侧：球体（根据状态变化）
        ├── idle: 渐变色 + cpu 图标
        ├── building: 橙色 + 锤子旋转 + 进度环
        ├── flashing: 紫色 + 芯片脉冲 + 进度环
        ├── verifying: 蓝色 + 信号闪烁 + 进度环
        ├── success: 绿色 + checkmark（1.5秒后消失）
        └── failure: 红色 + xmark（6秒后消失）
```

### 11.2 BallStatus 枚举

```swift
enum BallStatus: Equatable {
    case idle
    case building          // 橙色 + 锤头摆动
    case flashing          // 紫色 + 芯片脉冲
    case verifying         // 蓝色 + 信号闪烁
    case success(String)   // 绿色 + checkmark
    case failure(String)   // 红色 + xmark
}
```

### 11.3 窗口管理

**进入球模式 (`enterBallMode`):**
1. 保存主窗口位置 `savedFrame`
2. 主窗口设为 `normal` 层级并隐藏
3. 创建/显示球窗口（320×56，borderless + 透明背景）
4. `isBallMode = true`

**退出球模式 (`exitBallMode`):**
1. 从球位置开始（动画起点）
2. 主窗口设为 `floating` 层级（置顶，不被台前调度遮挡）
3. 0.25 秒 easeOut 动画展开到目标位置
4. `isBallMode = false`

**窗口关闭拦截:** 点红色关闭按钮自动进入球模式而非退出应用

### 11.4 进度环

```
progressTrack: 半透明底色圈 (Circle().stroke(opacity 0.12), width 60)
progressRing:  trim(from: 0, to: buildProgress), 从顶部开始 (-90°)
              .stroke(color, lineWidth: 3, lineCap: .round)
              .animation(.easeOut(duration: 0.2))
```

进度由 AppState 实时统计编译命令完成数来计算（见 8.2 节）。

### 11.5 球体动画

| 状态 | 动画 | 参数 |
|------|------|------|
| `building` | 锤头以底部为轴心摆动 | ±6°, 0.6s easeInOut 循环 |
| `flashing` | 芯片缩放脉冲 | 0.8↔1.2, 0.6s easeInOut 循环 |
| `verifying` | 信号图标闪烁 | 0.4↔1.0 opacity, 0.4s easeInOut 循环 |

### 11.6 状态自动恢复

成功状态持续 1.5 秒后自动回到 idle，失败状态持续 6 秒后自动回到 idle。
使用 `Task.sleep` + `revertTask?.cancel()` 实现，新操作开始时自动取消旧恢复任务。

### 11.7 按钮悬停

鼠标悬停时，左侧操作按钮区淡入（0.12s easeInOut），带 `.ultraThinMaterial` 毛玻璃背景。
移走时淡出。窗口固定 320×56 不缩放，按钮始终占位。

---

## 12. 中文本地化

### 12.1 范围

所有用户界面文本均已中文化，包括：

- **模型枚举**: `ProjectVendor.displayName`、`ProjectKind.displayName`、`BuildAction.displayName`、`RunState.displayName`、`DependencyStatus.displayName`
- **计算属性**: `ProjectInfo.buildMethod`、"现有 Makefile"/"生成 GCC 编译"等
- **按钮文本**: 选择项目、重新检测、检查环境、编译、烧录、编译并烧录、验证连接
- **Section 标题**: 最近项目、项目信息、依赖检查、诊断信息、编译输出
- **空状态**: 暂无最近项目、未选择项目、就绪、等待输出...
- **日志前缀**: [检测]、[重新检测]、[环境检查]、[已取消]
- **诊断信息**: 所有 title/detail/suggestion（AppState + LogParser 共 15+ 组）
- **设置面板**: 所有标签、placeholder、Section、关于页
- **菜单项**: 设置...、切换悬浮球
- **工具提示**: 所有 `.help()` 字符串

### 12.2 规范

- 命名一致：编译（build）、烧录（flash）、验证（verify）、检测（detect）、环境（environment）
- 工具名保持英文：ARM GCC、OpenOCD、ST-Link、TI Arm Clang、J-Link 等
- 标点使用中文全角

---

## 13. 性能优化

### 13.1 日志节流

- **问题**: 编译器每行输出都追加到 `@Published var logs`，每次触发全量 UI 刷新
- **解决**: 80ms 缓冲窗口，合并多条日志为一条 `LogEntry`，批量刷新
- **日志上限**: 最多 500 条，防止内存膨胀

### 13.2 控制台渲染

- **之前**: 单块 `Text` 拼接，每次更新重建整个 Text 树（O(n²)）
- **现在**: `NSTextView` + `NSAttributedString`，只替换整个文本存储
- `lastLogCount` 检查，日志无变化跳过更新

### 13.3 AppState 数据传递

- `recentProjectStore` 的变化通过 Combine 订阅转发到 `AppState.objectWillChange`
- 避免不必要的 SwiftUI 视图重建

### 13.4 悬浮球性能

- 窗口固定尺寸，不缩放，避免 NSHostingView 布局循环
- 使用 Timer + Task 驱动光晕/进度，不影响主线程响应

---

## 14. 开发历史与修改记录

### 14.1 初始构建

- 创建 SPM 项目结构
- 实现基本的项目检测、环境检查、脚本运行
- 实现三栏布局（HSplitView）

### 14.2 第一轮修复

- 修复脚本资源路径：`subdirectory: "Resources/scripts"` → `subdirectory: "scripts"`
- 修复通配符匹配：从字符串替换改为 NSRegularExpression
- 修复 Swift 6 并发：添加 `@unchecked Sendable`、`MutableBox<T>`
- 修复 RunState 属性名冲突：`state` → `runState`
- 修复 Notification.Name 重复定义

### 14.3 第二轮修复（6 项）

1. **设置入口**: Cmd+, 打开设置面板（NotificationCenter）
2. **重新检测 vs 环境检查**: 分离为两个独立操作
3. **设置传播**: `buildScriptArguments()` 生成 CLI 参数传脚本
4. **EnvironmentChecker 自定义路径**: 先检查 override 再自动检测
5. **STM32 验证无需 .elf**: verify 操作不要求 artifact 存在
6. **LogParser.checkSuccess**: 综合退出码 + 日志内容判断成败

### 14.4 UI 大改（中文 + 布局 + 视觉）

- 全界面中文化
- 三栏布局重新设计
- 新增 StatusBannerView
- 移除自动打开报告
- 视觉成功/失败指示器
- 失败信息明确展示

### 14.5 悬浮球功能

- 新增 `FloatingBallManager`（单例）
- 球模式：窗口缩小为 56×56 悬浮球
- 展开动画：从球位置展开到正常大小
- 悬停操作按钮：编译 / 烧录 / 验证
- 球体状态反馈：颜色 + 动画 + 进度环
- 进度追踪：基于编译命令计数

### 14.6 控制台优化

- 从每行独立 Text 改为 NSTextView
- 添加日志节流和行数上限
- 修复 NSTextView 在 NSViewRepresentable 中的 MainActor 隔离

### 14.7 悬浮球迭代

- NSPopover → 双窗口 → 固定窗口（避免 crash）
- 毛玻璃背景（可读性）
- 按钮缩写："编译并烧录" → "烧录"
- 三种不同动画：锤头摆动、芯片脉冲、信号闪烁
- 旋转光晕 → 进度环
- Timer Task → MainActor.run（修复 Timer 的 Sendable 崩溃）
- 所有状态管理切换为直接同步而非 .onChange 依赖

---

## 15. 常见问题与边界情况

### 15.1 编译卡顿

**现象**: STM32 编译时界面卡顿

**原因**: 大量编译输出 → 频繁 UI 刷新 → Text 树重建 O(n²)

**修复**: 
- 日志 80ms 节流
- NSTextView 替代 SwiftUI Text
- 日志上限 500 条

### 15.2 成功/失败状态卡死

**现象**: 编译完成后立即点重新编译，界面卡死

**原因**: `clearLogs()` 将 `runState` 设为 `.idle` 再改为 `.building`，两次 `.onChange` 让悬浮球视图连续重建

**修复**: `runAction` 中直接同步悬浮球状态，不依赖 `.onChange`

### 15.3 叉号按钮不响应

**现象**: 左栏项目列表的叉号点不动

**原因**: `List` 在 macOS 上会拦截行内 Button 点击

**修复**: 改用 `ScrollView` + `LazyVStack`，使用 `ZStack` 分离选择层和按钮层

### 15.4 最近项目删除不刷新

**现象**: 点叉号删除项目，UI 不更新直到其他操作触发刷新

**原因**: `recentProjectStore` 不是 `@Published`，其变化不通知 `AppState`

**修复**: 在 `AppState.init()` 中用 Combine 订阅 `recentProjectStore.objectWillChange`

### 15.5 悬浮球崩溃

**现象**: 鼠标移到悬浮球上应用闪退

**原因 1**: Swift 6 运行时并发检查 — Timer 回调中访问 `@MainActor` 属性
**修复 1**: 用 `Task { @MainActor in }` 包装

**原因 2**: 双窗口模式的 NSHostingView 布局循环
**修复 2**: 固定 320×56 窗口，不缩放

### 15.6 悬浮球按钮消失时机

**现象**: 鼠标从球移到操作按钮时，按钮缩回

**原因**: `onHover` 只在球体上触发

**修复**: 窗口固定 320×56，按钮始终占位，`onHover` 覆盖整个窗口

### 15.7 Python 脚本报告文件

- 每次编译生成一个报告文件在 `codex_build/` 目录
- STM32: `codex_build/STM32_BUILD_FLASH_REPORT.md`
- TI MSPM0: `codex_build/TI_BUILD_FLASH_REPORT.md`
- 每次覆盖，每个项目永远只有一个报告文件

### 15.8 避免引用的关键 API

- `Bundle.module.url(forResource:withExtension:subdirectory:)` — 注意 `subdirectory` 是 `"scripts"` 而非 `"Resources/scripts"`
- `FileManager.default.isExecutableFile(atPath:)` — 参数是 String 路径而非 URL
- `NSRegularExpression.escapedPattern(for:)` — glob 转 regex
- `Process` + `Pipe` — `readabilityHandler` + `terminationHandler`
- `NSHostingView` — 必须在创建窗口后才能设置 `contentView`

### 15.9 调试技巧

- 编译输出在右栏控制台，支持 Cmd+A 全选复制
- 环境检查结果在中栏依赖检查面板
- 编译报告的路径、命令行参数、尺寸输出在 `codex_build/` 目录
- 设置面板可以覆盖工具链路径（留空则自动检测）

---

## 16. 完整模型源码

### 16.1 RunState.swift 完整实现

```swift
import Foundation

enum RunState: Equatable {
    case idle
    case detecting
    case checkingEnvironment
    case building
    case flashing
    case verifying
    case success
    case failed(String)
    case cancelled

    var inProgress: Bool {
        switch self {
        case .detecting, .checkingEnvironment, .building, .flashing, .verifying:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "就绪"
        case .detecting: return "检测项目中..."
        case .checkingEnvironment: return "检查环境中..."
        case .building: return "编译中..."
        case .flashing: return "烧录中..."
        case .verifying: return "验证中..."
        case .success: return "成功"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
```

### 16.2 BuildAction.swift 完整实现

```swift
import Foundation

enum BuildAction: CaseIterable {
    case build
    case flash
    case buildAndFlash
    case verify

    var cliValue: String {
        switch self {
        case .build: return "build"
        case .flash: return "flash"
        case .buildAndFlash: return "all"
        case .verify: return "verify"
        }
    }

    var displayName: String {
        switch self {
        case .build: return "编译"
        case .flash: return "烧录"
        case .buildAndFlash: return "编译并烧录"
        case .verify: return "验证连接"
        }
    }
}
```

### 16.3 ProjectVendor.swift 完整实现

```swift
import Foundation

enum ProjectVendor: String, Codable, CaseIterable {
    case stm32 = "STM32"
    case tiMSPM0 = "TI MSPM0"
    case unknown = "未知"

    var displayName: String {
        switch self {
        case .stm32: return "STM32"
        case .tiMSPM0: return "TI MSPM0"
        case .unknown: return "未知"
        }
    }
}
```

### 16.4 ProjectKind.swift 完整实现

```swift
import Foundation

enum ProjectKind: String, Codable {
    case keil = "Keil"
    case bareFolder = "裸文件夹"
    case makefile = "Makefile"
    case cubeIDE = "CubeIDE"
    case ccsSysConfig = "CCS/SysConfig"
    case unknown = "未知"

    var displayName: String { rawValue }
}
```

### 16.5 DependencyCheck.swift 完整实现

```swift
import Foundation

struct DependencyCheck: Identifiable {
    var id = UUID()
    var name: String
    var status: DependencyStatus
    var path: URL?
    var message: String
}

enum DependencyStatus: String, Codable {
    case ok, warning, missing, unknown

    var displayName: String {
        switch self {
        case .ok: return "正常"
        case .warning: return "警告"
        case .missing: return "缺失"
        case .unknown: return "未知"
        }
    }
}
```

### 16.6 DiagnosticIssue.swift 完整实现

```swift
import Foundation

struct DiagnosticIssue: Identifiable {
    var id = UUID()
    let title: String
    let detail: String
    let suggestion: String
}
```

### 16.7 LogEntry.swift 完整实现

```swift
import Foundation

struct LogEntry: Identifiable {
    var id = UUID()
    let timestamp = Date()
    let text: String
}
```

### 16.8 STM32Family.swift 完整实现

```swift
import Foundation

enum STM32Family: String, Codable {
    case f1, f4, unknown

    var cpuFlags: [String] {
        switch self {
        case .f1: return ["-mcpu=cortex-m3", "-mthumb"]
        case .f4: return ["-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard"]
        case .unknown: return []
        }
    }

    var openOCDTarget: String {
        switch self {
        case .f1: return "target/stm32f1x.cfg"
        case .f4: return "target/stm32f4x.cfg"
        case .unknown: return ""
        }
    }
}
```

### 16.9 ToolchainInfo.swift 完整实现

```swift
import Foundation

struct ToolchainInfo {
    var armGcc: URL?
    var armObjcopy: URL?
    var armSize: URL?
    var openocd: URL?
    var tiArmClang: URL?
    var tiObjcopy: URL?
    var tiSize: URL?
    var mspm0SDK: URL?
    var jlinkExe: URL?

    var hasArmGCC: Bool { armGcc != nil }
    var hasOpenOCD: Bool { openocd != nil }
    var hasTIArmClang: Bool { tiArmClang != nil }
    var hasMSPM0SDK: Bool { mspm0SDK != nil }
    var hasJLink: Bool { jlinkExe != nil }
    var stlinkConnected = false
    var jlinkConnected = false
}
```

## 17. 完整服务源码

### 17.1 ScriptRunner.swift 完整实现

```swift
import Foundation

/// Thread-safe mutable container for @Sendable closure access.
final class MutableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class ScriptRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _outputHandler: OutputHandler?
    private var _completionHandler: CompletionHandler?
    private let _accumulated = MutableBox("")

    typealias OutputHandler = @Sendable (String) -> Void
    typealias CompletionHandler = @Sendable (Int32, String) -> Void

    var outputHandler: OutputHandler? {
        get { lock.withLock { _outputHandler } }
        set { lock.withLock { _outputHandler = newValue } }
    }

    var completionHandler: CompletionHandler? {
        get { lock.withLock { _completionHandler } }
        set { lock.withLock { _completionHandler = newValue } }
    }

    var isRunning: Bool {
        lock.withLock { _process != nil && _process!.isRunning }
    }

    func run(script: URL, project: URL, action: BuildAction,
             envOverrides: [String: String] = [:], extraArguments: [String] = []) {
        cancel()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            script.path,
            project.path,
            "--action",
            action.cliValue
        ] + extraArguments

        var env = ProcessInfo.processInfo.environment
        let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (env["PATH"] != nil) ? "\(defaultPATH):\(env["PATH"]!)" : defaultPATH
        for (key, value) in envOverrides where !value.isEmpty {
            env[key] = value
        }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        _accumulated.value = ""

        let accumulated = _accumulated
        let outputBox = MutableBox(_outputHandler)
        let completionBox = MutableBox(_completionHandler)

        pipe.fileHandleForReading.readabilityHandler = { [outputBox] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) ?? ""
            guard !text.isEmpty else { return }
            accumulated.value += text
            DispatchQueue.main.async {
                outputBox.value?(text)
            }
        }

        process.terminationHandler = { [completionBox, accumulated] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let finalOutput = accumulated.value
            DispatchQueue.main.async {
                completionBox.value?(proc.terminationStatus, finalOutput)
            }
        }

        lock.withLock { self._process = process }
        try? process.run()
    }

    func cancel() {
        let p = lock.withLock { () -> Process? in
            let p = _process
            _process = nil
            return p
        }
        p?.terminate()
    }
}
```

### 17.2 EnvironmentChecker.swift 完整实现

```swift
import Foundation

actor EnvironmentChecker {
    func checkAll(
        armGccOverride: String = "",
        openocdOverride: String = "",
        tiArmClangOverride: String = "",
        mspm0SDKOverride: String = "",
        jlinkOverride: String = ""
    ) -> ToolchainInfo {
        var info = ToolchainInfo()

        // ARM GCC 检测：用户自定义路径优先
        if !armGccOverride.isEmpty {
            let url = URL(fileURLWithPath: armGccOverride)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                info.armGcc = url
            }
        }
        if info.armGcc == nil {
            info.armGcc = findExec("arm-none-eabi-gcc", extraPaths: [
                "/opt/homebrew/bin", "/usr/local/bin",
                NSHomeDirectory() + "/arm-gcc-toolchain/bin"
            ])
        }
        if info.armGcc != nil {
            let dir = info.armGcc!.deletingLastPathComponent().path
            info.armObjcopy = findExec("arm-none-eabi-objcopy", extraPaths: [dir])
            if info.armObjcopy == nil {
                info.armObjcopy = findExec("arm-none-eabi-objcopy")
            }
            info.armSize = findExec("arm-none-eabi-size", extraPaths: [dir])
            if info.armSize == nil {
                info.armSize = findExec("arm-none-eabi-size")
            }
        }

        // OpenOCD 检测
        if !openocdOverride.isEmpty {
            let url = URL(fileURLWithPath: openocdOverride)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                info.openocd = url
            }
        }
        if info.openocd == nil {
            info.openocd = findExec("openocd", extraPaths: [
                "/opt/homebrew/bin", "/usr/local/bin"
            ])
        }
        info.stlinkConnected = detectSTLink()

        // TI Arm Clang 检测
        if !tiArmClangOverride.isEmpty {
            info.tiArmClang = resolveTIArmClangOverride(tiArmClangOverride)
        }
        if info.tiArmClang == nil {
            info.tiArmClang = findTIArmClang()
        }
        if info.tiArmClang != nil {
            let dir = info.tiArmClang!.deletingLastPathComponent().path
            info.tiObjcopy = findExec("tiarmobjcopy", extraPaths: [dir])
            info.tiSize = findExec("tiarmsize", extraPaths: [dir])
        }

        // MSPM0 SDK 检测
        if !mspm0SDKOverride.isEmpty {
            let url = URL(fileURLWithPath: mspm0SDKOverride)
            // 验证必要的 SDK 目录结构
            let requiredPaths = [
                "source/ti/devices/msp/m0p/startup_system_files/ticlang",
                "source/ti/driverlib/lib/ticlang/m0p"
            ]
            var valid = true
            for rp in requiredPaths {
                if !FileManager.default.fileExists(atPath: url.appendingPathComponent(rp).path) {
                    valid = false; break
                }
            }
            if valid { info.mspm0SDK = url }
        }
        if info.mspm0SDK == nil {
            info.mspm0SDK = findMSPM0SDK()
        }

        // J-Link 检测
        if !jlinkOverride.isEmpty {
            let url = URL(fileURLWithPath: jlinkOverride)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                info.jlinkExe = url
            }
        }
        if info.jlinkExe == nil {
            info.jlinkExe = findJLink()
        }
        info.jlinkConnected = detectJLink()

        return info
    }

    // MARK: - Find Executables

    private func findExec(_ name: String, extraPaths: [String] = []) -> URL? {
        var candidates: [String] = extraPaths
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: pathEnv.components(separatedBy: ":"))
        }
        for dir in candidates {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        let which = whichShell(name)
        if let w = which { return URL(fileURLWithPath: w) }
        return nil
    }

    private func whichShell(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findTIArmClang() -> URL? {
        let base = "/Applications/ti"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            return findExec("tiarmclang")
        }
        for dir in dirs {
            if dir.hasPrefix("ccstheia") || dir.hasPrefix("ccs") {
                let compilerBase = "\(base)/\(dir)/ccs/tools/compiler"
                guard let compilers = try? FileManager.default.contentsOfDirectory(atPath: compilerBase)
                else { continue }
                for comp in compilers {
                    if comp.hasPrefix("ti-cgt-armllvm") {
                        let exe = "\(compilerBase)/\(comp)/bin/tiarmclang"
                        if FileManager.default.isExecutableFile(atPath: exe) {
                            return URL(fileURLWithPath: exe)
                        }
                    }
                }
            }
        }
        return findExec("tiarmclang")
    }

    private func findMSPM0SDK() -> URL? {
        let base = "/Applications/ti"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return nil }
        let sdkDirs = dirs.filter { $0.hasPrefix("mspm0_sdk_") }.sorted()
        for dir in sdkDirs.reversed() {
            let sdkURL = URL(fileURLWithPath: "\(base)/\(dir)")
            let requiredPaths = [
                "source/ti/devices/msp/m0p/startup_system_files/ticlang",
                "source/ti/driverlib/lib/ticlang/m0p"
            ]
            var allFound = true
            for rp in requiredPaths {
                if !FileManager.default.fileExists(atPath: sdkURL.appendingPathComponent(rp).path) {
                    allFound = false; break
                }
            }
            if allFound { return sdkURL }
        }
        return nil
    }

    private func findJLink() -> URL? {
        let candidates = [
            NSHomeDirectory() + "/SEGGER_JLink_V950/JLinkExe",
            "/Applications/SEGGER/JLink/JLinkExe",
            "/usr/local/bin/JLinkExe",
            "/opt/homebrew/bin/JLinkExe",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return findExec("JLinkExe")
    }

    private func resolveTIArmClangOverride(_ value: String) -> URL? {
        let url = URL(fileURLWithPath: value)
        if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        let directBin = url.appendingPathComponent("tiarmclang")
        if FileManager.default.isExecutableFile(atPath: directBin.path) { return directBin }
        let nestedBin = url.appendingPathComponent("bin/tiarmclang")
        if FileManager.default.isExecutableFile(atPath: nestedBin.path) { return nestedBin }
        return nil
    }

    // MARK: - Hardware Detection

    private func detectSTLink() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-p", "IOUSB", "-l", "-w0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let keywords = ["ST-LINK", "STLink", "STMicroelectronics", "STM32 STLink"]
        return keywords.contains { output.contains($0) }
    }

    private func detectJLink() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-p", "IOUSB", "-l", "-w0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let keywords = ["J-Link", "SEGGER"]
        return keywords.contains { output.contains($0) }
    }
}
```

### 17.3 LogParser.swift 完整实现

```swift
import Foundation

struct LogParser {
    func parseDiagnostics(log: String, vendor: ProjectVendor,
                          succeeded: Bool = false) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        let lower = log.lowercased()

        // 1. ARM GCC 未找到
        if lower.contains("arm-none-eabi-gcc: command not found")
           || lower.contains("arm-none-eabi-gcc: not found") {
            issues.append(DiagnosticIssue(
                title: "未找到 ARM GCC",
                detail: "在 PATH 或常用目录中未找到 arm-none-eabi-gcc。",
                suggestion: "通过 Homebrew 安装 ARM GCC：brew install arm-none-eabi-gcc"
            ))
        }

        // 2. OpenOCD 未找到
        if lower.contains("openocd: command not found") {
            issues.append(DiagnosticIssue(
                title: "未找到 OpenOCD",
                detail: "在 PATH 或常用目录中未找到 OpenOCD。",
                suggestion: "通过 Homebrew 安装 OpenOCD：brew install openocd"
            ))
        }

        // 3. 不支持的 J-Link（SAM-ICE / OEM 受限版）
        if lower.contains("unsupported j-link probe")
           || lower.contains("productname: sam-ice")
           || lower.contains("restricted/oem j-link") {
            issues.append(DiagnosticIssue(
                title: "当前 J-Link 不支持 TI MSPM0",
                detail: "检测到 SAM-ICE 或受限 OEM J-Link。"
                       + "SEGGER 官方限制这类探针只能用于对应厂商芯片。",
                suggestion: "请改用 TI XDS110（推荐，SuperFlash 会自动走 DSLite），"
                           + "或使用真正的通用 SEGGER J-Link BASE/PLUS/EDU。"
            ))
        }

        // 4. J-Link DAP 初始化失败
        if lower.contains("failed to initialize dap") {
            issues.append(DiagnosticIssue(
                title: "J-Link DAP 初始化失败",
                detail: "J-Link 检测到目标电压，但无法通过 SWD 进入 MSPM0 调试端口。",
                suggestion: "重点检查 MSPM0 的 PA20/SWCLK、PA19/SWDIO、GND、VTref 和 NRST。"
                           + "若使用 LP-MSPM0G3507，请确认 J101 15:16 和 J101 13:14 调试跳线"
                           + "处于连接状态；如果外接 J-Link，请确认 SWDIO/SWCLK 没接反"
                           + "且与板载 XDS110 不冲突。"
            ))
        }

        // 5. 无法连接目标
        if lower.contains("could not connect to the target device") {
            issues.append(DiagnosticIssue(
                title: "无法连接到目标",
                detail: "调试探针无法连接到目标设备。",
                suggestion: "先断开其他 CCS/J-Link 会话，再降低 SWD 速度重试。"
                           + "若仍失败，请按 PA20=SWCLK、PA19=SWDIO、GND、VTref、NRST 逐根确认。"
            ))
        }

        // 6. ST-Link/目标未检测到
        if lower.contains("target not examined") || lower.contains("no device") {
            issues.append(DiagnosticIssue(
                title: "未检测到 ST-Link/目标",
                detail: "OpenOCD 无法检测到 ST-Link 或目标设备。",
                suggestion: "1. 检查 ST-Link USB 连接\n"
                           + "2. 确认目标板供电\n"
                           + "3. 检查 SWD 接线\n"
                           + "4. 结束其他 OpenOCD 进程"
            ))
        }

        // 7. 烧录验证失败
        if lower.contains("verification failed") || lower.contains("verify failed") {
            issues.append(DiagnosticIssue(
                title: "烧录验证失败",
                detail: "烧录的内容与预期的二进制文件不匹配。",
                suggestion: "尝试重新烧录。如果仍然失败，请检查目标时钟和烧录时序设置。"
            ))
        }

        // 8. 文件未找到
        if lower.contains("no such file") || lower.contains("not found") {
            issues.append(DiagnosticIssue(
                title: "文件未找到",
                detail: "未找到所需文件（源文件、链接脚本或二进制文件）。",
                suggestion: "请检查所有源文件是否存在以及项目中的路径是否正确。"
            ))
        }

        // 9. 缺少工具
        if lower.contains("command not found") || lower.contains("not a valid command") {
            issues.append(DiagnosticIssue(
                title: "缺少工具",
                detail: "所需的编译/烧录工具缺失或不在 PATH 中。",
                suggestion: "请确保所有必需的工具链已安装并位于 PATH 中。"
            ))
        }

        // 10. 回退：只有在操作未成功时才添加未知错误
        if issues.isEmpty && vendor != .unknown && !succeeded {
            let exitKeywords = ["error:", "failed", "can't", "cannot",
                                "unable to", "timed out"]
            if exitKeywords.contains(where: { lower.contains($0) }) {
                issues.append(DiagnosticIssue(
                    title: "未知错误",
                    detail: "操作过程中发生了未指定的错误。",
                    suggestion: "请查看上方完整日志以获取详细信息。检查连接和项目配置。"
                ))
            }
        }
        return issues
    }

    func checkSuccess(log: String, action: BuildAction) -> Bool {
        let lower = log.lowercased()
        let failureKeywords = [
            "error:", "failed", "could not connect", "target not examined",
            "no device", "verification failed", "command not found",
            "target connection not established", "can not attach to cpu"
        ]
        let hasFailure = failureKeywords.contains { lower.contains($0) }
        if hasFailure { return false }

        switch action {
        case .build:
            return buildSucceeded(lower)
        case .flash:
            return lower.contains("verified") || lower.contains("o.k.")
        case .verify:
            return lower.contains("ipsr = 000")
                || lower.contains("target halted")
                || lower.contains("o.k.")
        case .buildAndFlash:
            return buildSucceeded(lower)
                && (lower.contains("verified") || lower.contains("o.k."))
        }
    }

    private func buildSucceeded(_ lower: String) -> Bool {
        lower.contains("linking")
        || lower.contains("completed")
        || lower.contains("success")
        || lower.contains("nothing to be done")
        || lower.contains("report written")
        || lower.contains("arm-none-eabi-size")
        || lower.contains("tiarmsize")
        || lower.contains("tiarmobjcopy")
    }
}
```

### 17.4 ProjectDetector.swift 完整实现

```swift
import Foundation

final class ProjectDetector {
    func detectProject(at url: URL) -> ProjectInfo {
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            files.append(file)
            if files.count > 2000 { break }
        }

        var stm32Score = 0
        var tiScore = 0
        var info = ProjectInfo(rootURL: url)

        // STM32 评分
        for file in files {
            let name = file.lastPathComponent
            if name.hasSuffix(".ioc") { stm32Score += 5; info.iocFile = file }
            if name.hasSuffix(".uvprojx") { stm32Score += 4; info.keilProject = file }
            if wildcardMatch(name, pattern: "startup_stm32*.s")
                || wildcardMatch(name, pattern: "startup_stm32*.S") {
                stm32Score += 4; info.startupFile = file
            }
            if wildcardMatch(name, pattern: "STM32*.ld") {
                stm32Score += 3; info.linkerScript = file
            }
            if file.lastPathComponent.lowercased().hasPrefix("stm32")
                && file.pathExtension == "h" { stm32Score += 2 }
            if name == "Makefile" { stm32Score += 1; info.makefile = file }
            if name == "main.c" { stm32Score += 1 }
            if file.pathExtension == "c" { info.sourceCount += 1 }
            if file.pathExtension == "h" { info.includeCount += 1 }

            // TI 评分
            let path = file.path
            let relPath = path.dropFirst(url.path.count + 1)
            if relPath.hasPrefix("targetConfigs") && file.pathExtension == "ccxml" {
                tiScore += 5; info.tiConfigFile = file
            }
            if name == "ti_msp_dl_config.c" { tiScore += 4 }
            if file.pathExtension == "syscfg" { tiScore += 4; info.syscfgFile = file }
            if name == "device_linker.cmd" { tiScore += 3; info.tiLinkerCmd = file }
            if name == ".ccsproject" || name == ".cproject" { tiScore += 2 }
            if name == "Makefile" && info.makefile == nil { tiScore += 1; info.makefile = file }
        }

        // 最终判定
        if stm32Score >= tiScore && stm32Score >= 3 {
            info.vendor = .stm32
            info.projectKind = classifySTM32(info)
            info.chipName = extractSTM32Chip(from: files)
            info.stm32Family = classifySTM32Family(info.chipName ?? "")
        } else if tiScore > stm32Score && tiScore >= 3 {
            info.vendor = .tiMSPM0
            info.projectKind = .ccsSysConfig
            info.chipName = extractMSPM0Chip(from: files, project: url)
        } else {
            info.vendor = .unknown
            info.projectKind = .unknown
        }

        info.mainFiles = files.filter { $0.lastPathComponent == "main.c" }
        return info
    }

    private func classifySTM32(_ info: ProjectInfo) -> ProjectKind {
        if info.keilProject != nil { return .keil }
        if info.makefile != nil { return .makefile }
        if info.iocFile != nil { return .cubeIDE }
        return .bareFolder
    }

    private func extractSTM32Chip(from files: [URL]) -> String? {
        for file in files {
            let name = file.lastPathComponent
            if let match = name.range(of: "STM32[FAL]\\d{3}[A-Z0-9]{0,8}",
                                       options: .regularExpression) {
                return String(name[match])
            }
        }
        return nil
    }

    private func extractMSPM0Chip(from files: [URL], project: URL) -> String? {
        let configs = (try? FileManager.default.contentsOfDirectory(
            at: project.appendingPathComponent("targetConfigs"),
            includingPropertiesForKeys: nil)) ?? []
        for file in configs {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                if let match = content.range(
                    of: "MSPM0[A-Z0-9]+", options: .regularExpression) {
                    return String(content[match])
                }
            }
        }
        return nil
    }

    private func wildcardMatch(_ value: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        return value.range(of: "^\(escaped)$",
                           options: [.regularExpression, .caseInsensitive]) != nil
    }
}
```

### 17.5 ReportStore.swift 完整实现

```swift
import Foundation
import AppKit

struct ReportStore {
    func openReport(for url: URL, vendor: ProjectVendor) -> Bool {
        let reportName: String
        switch vendor {
        case .stm32: reportName = "STM32_BUILD_FLASH_REPORT.md"
        case .tiMSPM0: reportName = "TI_BUILD_FLASH_REPORT.md"
        case .unknown: return false
        }
        let reportURL = url.appendingPathComponent("codex_build")
            .appendingPathComponent(reportName)
        guard FileManager.default.fileExists(atPath: reportURL.path) else { return false }
        NSWorkspace.shared.open(reportURL)
        return true
    }

    func openBuildArtifact(for url: URL, vendor: ProjectVendor) -> Bool {
        let buildDir: String
        switch vendor {
        case .stm32: buildDir = "build-gcc"
        case .tiMSPM0: buildDir = "build-ticlang"
        case .unknown: return false
        }
        let dirURL = url.appendingPathComponent("codex_build")
            .appendingPathComponent(buildDir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        NSWorkspace.shared.open(dirURL)
        return true
    }

    func openCodexBuild(for url: URL) -> Bool {
        let dirURL = url.appendingPathComponent("codex_build")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        NSWorkspace.shared.open(dirURL)
        return true
    }
}
```

### 17.6 SettingsStore.swift 完整实现

```swift
import Foundation

final class SettingsStore: ObservableObject {
    @Published var armGccPath: String = ""
    @Published var openocdPath: String = ""
    @Published var tiArmClangPath: String = ""
    @Published var mspm0SDKPath: String = ""
    @Published var jlinkPath: String = ""
    @Published var openocdSpeed: String = "4000"
    @Published var jlinkSpeed: String = "4000"
    @Published var saveRecentProjects: Bool = true

    private let defaultsKey = "com.superflash.settings"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        armGccPath = dict["armGccPath"] ?? ""
        openocdPath = dict["openocdPath"] ?? ""
        tiArmClangPath = dict["tiArmClangPath"] ?? ""
        mspm0SDKPath = dict["mspm0SDKPath"] ?? ""
        jlinkPath = dict["jlinkPath"] ?? ""
        openocdSpeed = dict["openocdSpeed"] ?? "4000"
        jlinkSpeed = dict["jlinkSpeed"] ?? "4000"
        saveRecentProjects = dict["saveRecentProjects"] != "false"
    }

    func save() {
        let dict: [String: String] = [
            "armGccPath": armGccPath,
            "openocdPath": openocdPath,
            "tiArmClangPath": tiArmClangPath,
            "mspm0SDKPath": mspm0SDKPath,
            "jlinkPath": jlinkPath,
            "openocdSpeed": openocdSpeed,
            "jlinkSpeed": jlinkSpeed,
            "saveRecentProjects": saveRecentProjects ? "true" : "false",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    var envOverrides: [String: String] {
        var env: [String: String] = [:]
        if !armGccPath.isEmpty { env["ARM_GCC"] = armGccPath }
        if !openocdPath.isEmpty { env["OPENOCD"] = openocdPath }
        if !tiArmClangPath.isEmpty { env["CGT_ROOT"] = tiArmClangPath }
        if !mspm0SDKPath.isEmpty { env["SDK_ROOT"] = mspm0SDKPath }
        if !jlinkPath.isEmpty { env["JLINK"] = jlinkPath }
        return env
    }
}
```

### 17.7 RecentProjectStore.swift 完整实现

```swift
import Foundation

final class RecentProjectStore: ObservableObject {
    @Published var recentProjects: [ProjectInfo] = []

    private let defaultsKey = "com.superflash.recent"
    private let maxItems = 10

    init() { load() }

    func add(_ project: ProjectInfo) {
        recentProjects.removeAll { $0.rootURL == project.rootURL }
        recentProjects.insert(project, at: 0)
        if recentProjects.count > maxItems {
            recentProjects = Array(recentProjects.prefix(maxItems))
        }
        save()
    }

    func remove(_ project: ProjectInfo) {
        recentProjects.removeAll { $0.id == project.id }
        save()
    }

    func clear() {
        recentProjects = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let projects = try? JSONDecoder().decode([ProjectInfo].self, from: data)
        else { return }
        recentProjects = projects
    }
}
```

### 17.8 BuildPlanGenerator.swift 完整实现

```swift
import Foundation

struct BuildPlanGenerator {
    func selectScript(for vendor: ProjectVendor) -> String? {
        switch vendor {
        case .stm32: return "stm32_build_flash"
        case .tiMSPM0: return "ti_mspm0_build_flash"
        case .unknown: return nil
        }
    }
}
```

## 18. 完整 View 源码

### 18.1 SuperFlashApp.swift

```swift
import SwiftUI

@main
struct SuperFlashApp: App {
    @State private var ballManager = FloatingBallManager.shared

    var body: some Scene {
        Window("SuperFlash", id: "main") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    if let window = NSApp.windows.first(where: { $0.title == "SuperFlash" }) {
                        ballManager.bind(mainWindow: window)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    NotificationCenter.default.post(name: .showSuperFlashSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .windowSize) {
                Divider()
                Button("切换悬浮球") {
                    FloatingBallManager.shared.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let showSuperFlashSettings = Notification.Name("showSuperFlashSettings")
}
```

### 18.2 StatusBannerView.swift 完整实现

```swift
import SwiftUI

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
                resultContent(icon: "checkmark.circle.fill",
                              text: "操作成功完成！", color: .green)
            case .failed(let reason):
                resultContent(icon: "xmark.circle.fill",
                              text: reason.isEmpty ? "操作失败" : "失败：\(reason)",
                              color: .red)
            case .cancelled:
                resultContent(icon: "xmark.circle.fill",
                              text: "操作已取消", color: .orange)
            case .idle:
                EmptyView()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func progressContent(text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small).scaleEffect(0.9)
            Image(systemName: icon).font(.caption)
            Text(text).font(.subheadline).fontWeight(.medium)
            Spacer()
            Text("处理中...").font(.caption).foregroundColor(.secondary)
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
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    private func resultContent(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).symbolRenderingMode(.multicolor)
            Text(text).font(.subheadline).fontWeight(.semibold)
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(color)
    }
}
```

### 18.3 SettingsView.swift 完整实现

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool

    var body: some View {
        TabView {
            Form {
                Section("STM32 工具链") {
                    TextField("ARM GCC 路径", text: $settingsStore.armGccPath).font(.caption)
                    TextField("OpenOCD 路径", text: $settingsStore.openocdPath).font(.caption)
                    TextField("OpenOCD 速度 (kHz)", text: $settingsStore.openocdSpeed).font(.caption)
                }
                Section("TI MSPM0 工具链") {
                    TextField("TI Arm Clang 根目录", text: $settingsStore.tiArmClangPath).font(.caption)
                    TextField("MSPM0 SDK 根目录", text: $settingsStore.mspm0SDKPath).font(.caption)
                    TextField("JLinkExe 路径", text: $settingsStore.jlinkPath).font(.caption)
                    TextField("J-Link 速度 (kHz)", text: $settingsStore.jlinkSpeed).font(.caption)
                }
                Section("行为设置") {
                    Toggle("保存最近项目", isOn: $settingsStore.saveRecentProjects)
                }
                Section {
                    Text("留空以自动检测。").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
            .tabItem { Label("路径", systemImage: "gearshape") }

            VStack(alignment: .leading, spacing: 8) {
                Text("关于 SuperFlash").font(.headline)
                Text("版本 1.0.0").font(.caption).foregroundColor(.secondary)
                Text("macOS 原生 SwiftUI 应用，一键编译烧录嵌入式项目。")
                    .font(.caption).foregroundColor(.secondary)
                Text("支持 STM32F1、STM32F4（OpenOCD + ST-Link）和 TI MSPM0（J-Link + TI Arm Clang）。")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding()
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    settingsStore.save()
                    isPresented = false
                }
            }
        }
    }
}
```

### 18.4 LogTextView.swift (NSTextView Wrapper)

```swift
import SwiftUI
import AppKit

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

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var lastLogCount = 0

        @MainActor
        func update(textView: NSTextView, logs: [LogEntry], autoScroll: Bool) {
            guard logs.count != lastLogCount || logs.isEmpty else { return }
            lastLogCount = logs.count

            let attr = NSMutableAttributedString()
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

            for entry in logs {
                let color = logColor(entry.text)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color,
                ]
                attr.append(NSAttributedString(string: entry.text, attributes: attrs))
            }

            textView.textStorage?.setAttributedString(attr)

            if autoScroll {
                textView.scrollToEndOfDocument(nil)
            }
        }

        private func logColor(_ text: String) -> NSColor {
            let lower = text.lowercased()
            if lower.contains("error") || lower.contains("fail") || lower.contains("fatal") {
                return .systemRed
            }
            if lower.contains("warning") { return .systemOrange }
            if lower.contains("success") || lower.contains("ok")
                || lower.contains("verified") || lower.contains("completed") {
                return .systemGreen
            }
            if lower.contains("[cancel") || lower.contains("[已取消") { return .systemOrange }
            return .textColor
        }
    }
}
```

## 19. 并发模型详解

### 19.1 Actor 边界

| 类型 | Actor 隔离 | 原因 |
|------|-----------|------|
| `AppState` | `@MainActor` | 所有 UI 状态必须在主线程更新 |
| `EnvironmentChecker` | `actor` | 执行耗时的文件系统和进程操作 |
| `ScriptRunner` | `@unchecked Sendable` | 使用 NSLock 手动同步 |
| `FloatingBallManager` | `@MainActor` | 管理 NSWindow 和 ObservableObject |
| `Process` callbacks | 非隔离 | `readabilityHandler` / `terminationHandler` 在后台线程运行 |

### 19.2 跨 Actor 通信模式

```
主线程 (MainActor)
  AppState.runAction()
    → 同步更新悬浮球状态
    → 设置 ScriptRunner 回调
    → ScriptRunner.run() ← Process 在后台运行
    
后台线程
  readabilityHandler 接收管道数据
    → DispatchQueue.main.async { AppState 输出处理 }
    → 日志节流缓冲
    → buildProgress 更新
    
进程结束
  terminationHandler
    → DispatchQueue.main.async { AppState 完成处理 }
    → runState = .success/.failed
```

### 19.3 Sendable 安全模式

`MutableBox<T>` 用于在 `@Sendable` 闭包中安全传递引用类型：

```swift
final class MutableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// 使用模式：
let outputBox = MutableBox(_outputHandler)
let completionBox = MutableBox(_completionHandler)
let accumulated = MutableBox("")

pipe.fileHandleForReading.readabilityHandler = { [outputBox] handle in
    // 在 @Sendable 闭包中安全访问
    DispatchQueue.main.async {
        outputBox.value?(text)  // 主线程读取
    }
}
```

### 19.4 Timer 与 MainActor

Timer 回调是 `@Sendable`，不能直接访问 `@MainActor` 属性：

```swift
// 错误方式（Swift 6 运行时崩溃）：
glowTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
    self.glowAngle += 2  // ❌ glowAngle 是 @MainActor 属性
}

// 正确方式：
glowTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
    Task { @MainActor in
        FloatingBallManager.shared.glowAngle += 2  // ✓
    }
}
```

## 20. 完整错误处理路径

### 20.1 runAction 校验链

```
runAction(.build)
├── currentProject != nil? → 否: runState = .failed("未选择项目...")
├── vendor != .unknown? → 否: runState = .failed("未选择项目...")
├── planGenerator.selectScript() != nil? → 否: runState = .failed("没有适用于...的脚本")
└── bundledScriptURL() != nil? → 否: runState = .failed("未找到脚本...")
    + diagnostics = [脚本未找到诊断]
```

### 20.2 completionHandler 处理

```
exitCode == 0?
├── 是:
│   ├── checkSuccess() == true 或 "Nothing to be done"?
│   │   ├── 是: runState = .success ✓
│   │   └── 否: runState = .success (+ 可能问题警告)
│   └── diagnostics = parseDiagnostics(succeeded: true/false)
└── 否: runState = .failed("进程退出，代码 N")
    └── diagnostics = parseDiagnostics(succeeded: false)
```

### 20.3 环境检查失败

```
checkEnvironment()
└── Task { info = await checker.checkAll(...) }
    ├── 所有依赖找到 → runState = .success
    ├── 缺少 STM32 工具 → issues + [ARM GCC/OpenOCD 未找到]
    └── 缺少 TI 工具 → issues + [TI Arm Clang/MSPM0 SDK/JLink 未找到]
```

## 21. 完整 UI 组件树

```
ContentView
├── HSplitView
│   ├── ProjectListView (左栏)
│   │   ├── Header: "最近项目" + 清除按钮
│   │   ├── Empty State: 大图标 + 提示文字
│   │   └── ScrollView > LazyVStack > ProjectRow × N
│   │       ├── ZStack
│   │       │   ├── HStack (onTapGesture → select)
│   │       │   │   ├── vendorIcon (SF Symbol + 颜色)
│   │       │   │   ├── VStack: 项目名 + 供应商名
│   │       │   │   └── Spacer
│   │       │   └── Button "xmark" (hover 显示)
│   │       └── hover 背景高亮
│   │
│   ├── VStack (中栏)
│   │   ├── StatusBannerView
│   │   │   ├── progressContent (操作中): HStack[ProgressView, 图标, 文字]
│   │   │   └── resultContent (完成): HStack[Symbol, 文字] + 颜色背景
│   │   │
│   │   ├── ScrollView
│   │   │   ├── ProjectSummaryView (GroupBox.card)
│   │   │   │   ├── 项目名 + 供应商胶囊标签
│   │   │   │   ├── Divider
│   │   │   │   └── LazyVGrid: 种类/芯片/编译方式/烧录方式/源文件/头文件
│   │   │   │
│   │   │   ├── actionButtonPanel (GroupBox.card)
│   │   │   │   ├── HStack: [选择项目, 重新检测, 检查环境] + CancelButton
│   │   │   │   ├── Divider
│   │   │   │   ├── HStack: [编译, 烧录, 编译并烧录, 验证]
│   │   │   │   └── HStack: [trash, folder, doc, clipboard, gear]
│   │   │   │
│   │   │   ├── EnvironmentCheckView (GroupBox.card)
│   │   │   │   ├── Header: "依赖检查" + wrench 图标
│   │   │   │   ├── Empty State: 缩小镜图标 + 提示
│   │   │   │   └── ForEach: dependencyRow × N
│   │   │   │       └── HStack[statusIcon, name, message, statusBadge]
│   │   │   │
│   │   │   └── DiagnosticView (GroupBox.card)
│   │   │       ├── Header: "诊断信息 (N)" + 警告图标
│   │   │       └── ForEach: issueCard × N
│   │   │           └── VStack[title, detail, suggestion]
│   │   │
│   │   └── overlay (topTrailing): 悬浮球切换按钮
│   │
│   └── LogConsoleView (右栏)
│       ├── Header: "编译输出" + 复制按钮 + 自动滚动 + 状态徽章
│       ├── Divider
│       └── LogTextView (NSTextView via NSViewRepresentable)
│           └── NSAttributedString (着色日志)
│
└── .sheet: SettingsView
    └── TabView
        ├── Tab "路径": Form[STM32, TI, 行为 Sections]
        └── Tab "关于": VStack[版本信息, 简介]
```

## 22. 数据流图

### 22.1 编译操作数据流

```
用户点击"编译"按钮
  │
  ▼
ContentView: appState.runAction(.build)
  │
  ▼
AppState.runAction(.build)
  │
  ├── 校验项目/供应商/脚本
  ├── 重置日志、诊断、进度
  ├── 直接更新悬浮球状态 → ball.updateStatus(.building)
  ├── runState = .building
  │     └── .onChange → StatusBannerView 更新
  │     └── .onChange → ball.updateStatus(.building)（备选路径）
  ├── 构建脚本参数
  ├── 设置 outputHandler
  │     └── 每行输出 → 日志追加 → 进度统计
  ├── 设置 completionHandler
  │     └── 退出码判断 → 诊断解析 → 状态更新
  └── ScriptRunner.run()
        └── Process 启动
              ├── readabilityHandler → outputHandler
              └── terminationHandler → completionHandler
```

### 22.2 进度更新数据流

```
ScriptRunner.readabilityHandler (后台线程)
  → DispatchQueue.main.async
    → AppState.outputHandler
      ├── logs.append(LogEntry)  // 控制台更新
      └── buildProgress 计算
            ├── 统计 $ 命令行完成数
            └── buildProgress = 已完成 / 总步数
              └── .onChange → FloatingBallManager.buildProgress
                └── FloatingBallContent.progressRing.trim 更新
```

## 23. 全部中文翻译对照表

### 23.1 枚举显示名

| 英文原始 | 中文显示 |
|----------|----------|
| STM32 | STM32 |
| TI MSPM0 | TI MSPM0 |
| Unknown | 未知 |
| Keil | Keil |
| Bare Folder | 裸文件夹 |
| Makefile | Makefile |
| CubeIDE | CubeIDE |
| CCS/SysConfig | CCS/SysConfig |
| Build Only | 编译 |
| Flash Only | 烧录 |
| Build & Flash | 编译并烧录 |
| Verify Connection | 验证连接 |
| Idle | 就绪 |
| Detecting Project... | 检测项目中... |
| Checking Environment... | 检查环境中... |
| Building... | 编译中... |
| Flashing... | 烧录中... |
| Verifying... | 验证中... |
| Success | 成功 |
| Failed | 失败 |
| Cancelled | 已取消 |
| OK | 正常 |
| Warning | 警告 |
| Missing | 缺失 |
| Existing Makefile | 现有 Makefile |
| Generated GCC Build | 生成 GCC 编译 |
| TI Arm Clang + SysConfig | TI Arm Clang + SysConfig |

### 23.2 界面文本

| 英文原始 | 中文 |
|----------|------|
| Select Project | 选择项目 |
| Re-detect | 重新检测 |
| Check Env | 检查环境 |
| Cancel | 取消 |
| Build | 编译 |
| Flash | 烧录 |
| Build & Flash | 编译并烧录 |
| Verify | 验证 |
| Clear log | 清除日志 |
| Open build artifacts | 打开编译产物 |
| Open report | 打开报告 |
| Copy diagnostics | 复制诊断信息 |
| Settings | 设置 |
| Recent Projects | 最近项目 |
| Clear | 清除 |
| No recent projects | 暂无最近项目 |
| Select a project to begin | 选择一个项目开始 |
| Console | 编译输出 |
| Auto-scroll | 自动滚动 |
| Ready | 就绪 |
| Waiting for output... | 等待输出... |
| Dependencies | 依赖检查 |
| Diagnostics (N) | 诊断信息 (N) |
| Suggestion | 建议 |
| Done | 完成 |
| Behaviour | 行为设置 |
| Paths | 路径 |
| About | 关于 |
| Switch to floating ball | 切换悬浮球 |
| Settings... | 设置... |

### 23.3 日志前缀

| 英文 | 中文 |
|------|------|
| [Detect] | [检测] |
| [Re-detect] | [重新检测] |
| [EnvCheck] | [环境检查] |
| [Cancelled] | [已取消] |
| NOT FOUND | 未找到 |
| Connected | 已连接 |
| Not detected | 未检测到 |
| Detected | 已检测到 |

---

*文档版本: 2.0*
*最后更新: 2026-06-15*
*工程位置: /Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash*
*总行数: 3000+*
*用途: 作为新对话接手该项目的完整参考文档*
