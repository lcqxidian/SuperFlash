# SuperFlash 技术路线

## 1. 项目目标

SuperFlash 是一个 macOS 原生 SwiftUI 软件，用于选择嵌入式项目后一键完成：

- 项目识别
- 芯片识别
- 工具链检查
- 依赖检查
- 编译
- 烧录
- 连接/运行验证
- 日志和报告生成

第一版只给自己使用，不需要 App Store 分发，不需要沙盒，不需要自动安装工具链，只检测本机已有工具。

支持范围：

- STM32F1
- STM32F4
- TI MSPM0

优先适配项目类型：

- Keil 工程迁移
- 裸文件夹项目
- 已有 Makefile 项目
- TI MSPM0 CCS/SysConfig 项目

烧录方式：

- STM32：ST-Link + OpenOCD
- TI MSPM0：J-Link + TI Arm Clang + MSPM0 SDK

## 2. 总体设计原则

### 2.1 SwiftUI 负责产品体验

SwiftUI App 负责：

- 项目选择
- 检测结果展示
- 工具链状态展示
- 实时日志展示
- 按钮操作
- 进度和状态管理
- 错误诊断展示
- 最近项目管理

### 2.2 构建烧录逻辑先用脚本承载

第一版不要把所有编译烧录逻辑直接写进 Swift。

原因：

- Keil 工程迁移涉及 XML 解析、include path、define、source list、startup、linker script。
- 裸文件夹项目需要扫描源码、自动生成 Makefile、生成 linker script。
- TI MSPM0 需要处理 TI clang、MSPM0 SDK、SysConfig 输出、J-Link 脚本。
- 命令行工具输出复杂，失败不能只看退出码。
- Python 脚本更适合快速迭代和跨项目适配。

Swift App 应调用后端脚本：

- `scripts/stm32_build_flash.py`
- `scripts/ti_mspm0_build_flash.py`

后续稳定后，再考虑把部分逻辑迁移到 Swift。

### 2.3 不污染项目根目录

所有自动生成内容统一放到项目目录下：

```text
codex_build/
  STM32_BUILD_FLASH_REPORT.md
  TI_BUILD_FLASH_REPORT.md
  build-gcc/
  build-ticlang/
  generated/
  logs/
  openocd_flash.log
  jlink_flash.jlink
  jlink_verify.jlink
```

不要在项目根目录散落 Makefile、脚本、日志。

## 3. App 工程结构建议

### 3.1 推荐第一版工程形态

为了让 Claude 可以直接在命令行里创建、编译、运行，第一版推荐先做 Swift Package 可执行程序，而不是一开始手搓 `.xcodeproj`。

推荐结构：

```text
SuperFlash/
  Package.swift
  Sources/
    SuperFlash/
      SuperFlashApp.swift
      ...
      Resources/
        scripts/
          stm32_build_flash.py
          ti_mspm0_build_flash.py
```

`Package.swift` 使用：

```swift
.executableTarget(
    name: "SuperFlash",
    resources: [
        .copy("Resources/scripts")
    ]
)
```

开发期运行：

```sh
cd /Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash
swift run SuperFlash
```

第一版验收以 `swift run SuperFlash` 能打开原生 macOS 窗口为准。后续如果需要 `.app` 包，再用 Xcode 或 packaging 脚本包装。

注意：

- 第一版不要开启 App Sandbox。
- 如果后续转成 Xcode App target，需要确认 `com.apple.security.app-sandbox` 为 false 或移除 sandbox entitlement。
- 外部命令执行依赖 `Process`，沙盒会让访问项目目录和执行工具链变麻烦。

```text
SuperFlash/
  SuperFlashApp.swift

  App/
    AppState.swift
    AppConfig.swift

  Models/
    ProjectInfo.swift
    ProjectVendor.swift
    ProjectKind.swift
    ChipInfo.swift
    ToolchainInfo.swift
    DependencyCheck.swift
    BuildAction.swift
    RunState.swift
    LogEntry.swift
    DiagnosticIssue.swift

  Services/
    ProjectDetector.swift
    EnvironmentChecker.swift
    BuildPlanGenerator.swift
    ScriptRunner.swift
    LogParser.swift
    ReportStore.swift
    SettingsStore.swift
    RecentProjectStore.swift

  UI/
    ContentView.swift
    ProjectPickerView.swift
    ProjectListView.swift
    ProjectSummaryView.swift
    EnvironmentCheckView.swift
    ActionBarView.swift
    LogConsoleView.swift
    DiagnosticView.swift
    SettingsView.swift

  Resources/
    scripts/
      stm32_build_flash.py
      ti_mspm0_build_flash.py
```

### 3.2 可复用脚本来源

当前机器上已经有可复用的后端脚本。Claude 实现时不要重新发明第一版后端，先复制这些脚本进 App resources：

STM32：

```text
/Users/lcq/.codex/skills/stm32-build-flash/scripts/stm32_build_flash.py
/Users/lcq/.claude/skills/stm32-build-flash/scripts/stm32_build_flash.py
```

TI MSPM0：

```text
/Users/lcq/.codex/skills/ti-build-flash/scripts/ti_mspm0_build_flash.py
/Users/lcq/.claude/skills/ti-build-flash/scripts/ti_mspm0_build_flash.py
```

推荐优先从 `~/.claude/skills/...` 复制，因为后续是 Claude 接手实现。

复制后，App 运行时从 `Bundle.module` 找脚本路径，再用 `/usr/bin/python3` 执行。

脚本路径必须作为 `Process.arguments` 单独传入，不能拼接 shell 字符串。

## 4. 核心数据模型

### 4.1 ProjectVendor

```swift
enum ProjectVendor: String, Codable {
    case stm32
    case tiMSPM0
    case unknown
}
```

### 4.2 STM32Family

```swift
enum STM32Family: String, Codable {
    case f1
    case f4
    case unknown
}
```

### 4.3 ProjectKind

```swift
enum ProjectKind: String, Codable {
    case keil
    case bareFolder
    case makefile
    case cubeIDE
    case ccsSysConfig
    case unknown
}
```

### 4.4 BuildAction

```swift
enum BuildAction {
    case detect
    case build
    case flash
    case buildAndFlash
    case verify
}
```

### 4.5 RunState

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
}
```

### 4.6 ProjectInfo

```swift
struct ProjectInfo: Codable, Identifiable {
    var id: UUID
    var rootURL: URL
    var displayName: String
    var vendor: ProjectVendor
    var projectKind: ProjectKind
    var chipName: String?
    var stm32Family: STM32Family?

    var makefile: URL?
    var keilProject: URL?
    var iocFile: URL?
    var startupFile: URL?
    var linkerScript: URL?

    var syscfgFile: URL?
    var tiConfigFile: URL?
    var tiLinkerCmd: URL?

    var mainFiles: [URL]
    var sourceCount: Int
    var includeCount: Int
}
```

### 4.7 ToolchainInfo

```swift
struct ToolchainInfo {
    var armGcc: URL?
    var armObjcopy: URL?
    var armSize: URL?
    var openocd: URL?
    var stlinkConnected: Bool

    var tiArmClang: URL?
    var tiObjcopy: URL?
    var tiSize: URL?
    var mspm0SDK: URL?
    var jlinkExe: URL?
    var jlinkConnected: Bool
}
```

### 4.8 DependencyCheck

```swift
struct DependencyCheck: Identifiable {
    var id: UUID
    var name: String
    var status: DependencyStatus
    var path: URL?
    var message: String
}

enum DependencyStatus {
    case ok
    case warning
    case missing
    case unknown
}
```

## 5. UI 设计

### 5.1 第一版窗口布局

```text
┌──────────────────────────────────────────────────────────────┐
│ Toolbar: 选择项目  重新检测  设置                            │
├──────────────────────┬───────────────────────────────────────┤
│ 最近项目列表          │ 项目摘要                              │
│                      │ 工具链/依赖检查                       │
│                      │ 操作按钮                              │
│                      │ 实时日志                              │
│                      │ 错误诊断                              │
└──────────────────────┴───────────────────────────────────────┘
```

### 5.2 主要按钮

- 选择项目
- 重新检测
- 仅编译
- 仅烧录
- 编译并烧录
- 验证连接
- 打开产物目录
- 复制错误诊断
- 清空日志
- 取消任务

### 5.3 项目摘要展示

示例：

```text
项目类型：STM32
工程类型：Keil 工程迁移
芯片：STM32F407ZG
系列：STM32F4
构建方式：自动生成 GCC 构建
烧录方式：OpenOCD + ST-Link
状态：可编译，可烧录
```

TI 示例：

```text
项目类型：TI MSPM0
工程类型：CCS/SysConfig
芯片：MSPM0G3507
构建方式：TI Arm Clang + SysConfig 输出
烧录方式：J-Link
状态：可编译，可烧录
```

### 5.4 工具链检查展示

STM32：

```text
ARM GCC: /opt/homebrew/bin/arm-none-eabi-gcc
Objcopy: /opt/homebrew/bin/arm-none-eabi-objcopy
Size: /opt/homebrew/bin/arm-none-eabi-size
OpenOCD: /opt/homebrew/bin/openocd
ST-Link: 已连接 / 未连接
```

TI：

```text
TI Arm Clang: /Applications/ti/ccstheia151/...
MSPM0 SDK: /Applications/ti/mspm0_sdk_2_04_00_06
J-Link: /Users/lcq/SEGGER_JLink_V950/JLinkExe
J-Link Target: 已连接 / 未连接
```

## 6. ProjectDetector 设计

`ProjectDetector` 输入项目根目录，输出 `ProjectInfo`。

### 6.1 扫描规则

扫描深度建议第一版限制为 8 层，避免误扫大目录。

忽略目录：

```text
.git
.svn
build
Debug
Release
codex_build
DerivedData
node_modules
__pycache__
```

注意：TI MSPM0 的 `Debug/ti_msp_dl_config.c` 很重要，不能完全忽略 `Debug`。实现时可以：

- 通用扫描忽略 Debug
- TI 检测单独检查 `Debug/ti_msp_dl_config.c`

### 6.2 STM32 检测特征

认为是 STM32 的条件：

```text
*.ioc
*.uvprojx
*.uvproj
startup_stm32*.s
startup_stm32*.S
STM32*_FLASH.ld
Core/Src/main.c
Drivers/CMSIS
stm32f1xx.h
stm32f4xx.h
```

### 6.3 STM32F1 检测特征

```text
stm32f1xx
STM32F10X
startup_stm32f10x
STM32F103
STM32F101
STM32F105
STM32F107
target/stm32f1x.cfg
```

### 6.4 STM32F4 检测特征

```text
stm32f4xx
STM32F4xx
STM32F40_41xxx
startup_stm32f40_41xxx
STM32F401
STM32F407
STM32F411
STM32F429
target/stm32f4x.cfg
```

### 6.5 STM32 芯片名识别优先级

1. `.ioc`

   ```text
   Mcu.Name=STM32F407ZGTx
   ```

2. Keil `.uvprojx`

   常见字段：

   ```xml
   <Device>STM32F407ZG</Device>
   <Cpu>IRAM(...)</Cpu>
   ```

3. linker 文件名

   ```text
   STM32F407ZG_FLASH.ld
   ```

4. startup 文件名

   ```text
   startup_stm32f40_41xxx.s
   ```

5. 源码宏

   ```text
   STM32F40_41xxx
   STM32F10X_HD
   ```

6. 项目路径名

### 6.6 TI MSPM0 检测特征

认为是 TI MSPM0 的条件：

```text
targetConfigs/MSPM0*.ccxml
Debug/ti_msp_dl_config.c
Debug/ti_msp_dl_config.h
Debug/device_linker.cmd
Debug/device.cmd.genlibs
empty.syscfg
*.syscfg
MSPM0G3507
mspm0_sdk
```

### 6.7 TI 芯片名识别优先级

1. `targetConfigs/*.ccxml`
2. `Debug/device.opt`
3. `Debug/ti_msp_dl_config.h`
4. `.syscfg`
5. 项目路径名

常见结果：

```text
MSPM0G3507
MSPM0G3519
MSPM0L1306
```

### 6.8 工程类型识别

Keil：

```text
*.uvprojx
*.uvproj
*.uvoptx
```

裸文件夹：

```text
有 main.c
有 startup_stm32*.s
有 .ld 或可根据芯片生成 .ld
没有 Makefile
没有 CubeIDE/Keil/CCS 明确工程文件
```

Makefile：

```text
Makefile
makefile
```

CubeIDE：

```text
.project
.cproject
*.ioc
Core/
Drivers/
```

TI CCS/SysConfig：

```text
Debug/ti_msp_dl_config.c
Debug/device_linker.cmd
Debug/device.cmd.genlibs
empty.syscfg
targetConfigs/*.ccxml
```

## 7. EnvironmentChecker 设计

只检查本机已有工具，不自动安装。

### 7.1 ARM GCC

搜索：

```text
PATH
/opt/homebrew/bin/arm-none-eabi-gcc
/usr/local/bin/arm-none-eabi-gcc
~/arm-gcc-toolchain/bin/arm-none-eabi-gcc
```

同时检查：

```text
arm-none-eabi-objcopy
arm-none-eabi-size
```

### 7.2 OpenOCD

搜索：

```text
PATH
/opt/homebrew/bin/openocd
/usr/local/bin/openocd
```

验证：

```sh
openocd --version
```

### 7.3 ST-Link

第一层 USB 检测：

```sh
ioreg -p IOUSB -l -w0
```

关键词：

```text
ST-LINK
STLink
STMicroelectronics
STM32 STLink
```

第二层最终验证：OpenOCD 实际连接。

不要只依赖 USB 检测，因为 macOS 上 USB 查询有时不稳定。

### 7.4 TI Arm Clang

搜索：

```text
/Applications/ti/ccstheia*/ccs/tools/compiler/ti-cgt-armllvm_*/bin/tiarmclang
/Applications/ti/ccs*/ccs/tools/compiler/ti-cgt-armllvm_*/bin/tiarmclang
PATH
```

同时检查：

```text
tiarmobjcopy
tiarmsize
```

### 7.5 MSPM0 SDK

搜索：

```text
/Applications/ti/mspm0_sdk_*
```

需要存在：

```text
source/
source/ti/devices/msp/m0p/startup_system_files/ticlang/
source/ti/driverlib/lib/ticlang/m0p/
```

### 7.6 J-Link

搜索：

```text
PATH
/Users/lcq/SEGGER_JLink_V950/JLinkExe
/Applications/SEGGER/JLink/JLinkExe
/usr/local/bin/JLinkExe
/opt/homebrew/bin/JLinkExe
```

J-Link 检查不能只看退出码。

失败关键词：

```text
Failed to initialize DAP
Could not connect to the target device
Target connection not established
Can not attach to CPU
Mass erase failed
Factory reset failed
returned with error code
```

成功关键词：

```text
DAP initialized successfully
Found Cortex-M0
O.K.
IPSR = 000 (NoException)
```

## 8. BuildPlanGenerator 设计

输入：

- `ProjectInfo`
- `ToolchainInfo`
- 用户 action

输出：

- 应执行的脚本
- 参数
- 预期产物路径
- 失败诊断规则

### 8.1 STM32 + 已有 Makefile

优先复用 Makefile。

命令：

```sh
make TOOLCHAIN=/opt/homebrew/bin GNU_INSTALL_ROOT=/opt/homebrew/bin/
```

如果用户选择“仅烧录”，先查找已有 `.elf`。

产物查找顺序：

```text
build/*.elf
Debug/*.elf
Release/*.elf
codex_build/build-gcc/*.elf
**/*.elf
```

取最后修改时间最新的 `.elf`。

### 8.2 STM32 + Keil 工程迁移

第一版实现实用迁移，不追求完整支持所有 Keil 选项。

处理流程：

1. 找到 `.uvprojx`
2. XML 解析
3. 提取源码列表
4. 提取 include path
5. 提取 define
6. 提取 device/chip
7. 找 startup 文件
8. 找 linker script
9. 如果没有 linker script，根据芯片生成
10. 在 `codex_build/generated/` 生成 Makefile
11. 调用 ARM GCC 构建

Keil XML 重点字段：

```xml
<Device>STM32F407ZG</Device>
<FilePath>...</FilePath>
<IncludePath>...</IncludePath>
<Define>...</Define>
```

Keil 路径可能是 Windows 风格：

```text
.\USER\main.c
..\CORE\startup_stm32f10x_hd.s
```

需要转换：

- `\` -> `/`
- 相对路径基于 `.uvprojx` 所在目录
- 忽略不存在的文件

### 8.3 STM32 + 裸文件夹

自动扫描：

```text
*.c
startup_stm32*.s
*.ld
*.h 所在目录
```

忽略：

```text
build
Debug
Release
codex_build
.git
```

没有 `.ld` 时根据芯片生成。

F103C8：

```ld
FLASH ORIGIN = 0x08000000, LENGTH = 64K
RAM   ORIGIN = 0x20000000, LENGTH = 20K
```

F103ZE：

```ld
FLASH ORIGIN = 0x08000000, LENGTH = 512K
RAM   ORIGIN = 0x20000000, LENGTH = 64K
```

F407ZG：

```ld
FLASH  ORIGIN = 0x08000000, LENGTH = 1M
RAM    ORIGIN = 0x20000000, LENGTH = 128K
CCMRAM ORIGIN = 0x10000000, LENGTH = 64K
_estack = ORIGIN(RAM) + LENGTH(RAM)
```

### 8.4 STM32 编译参数

STM32F1：

```sh
-mcpu=cortex-m3 -mthumb
```

常见 define：

```text
STM32F10X_MD
STM32F10X_HD
USE_STDPERIPH_DRIVER
```

STM32F4：

```sh
-mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard
```

常见 define：

```text
STM32F40_41xxx
STM32F4xx
USE_STDPERIPH_DRIVER
USE_HAL_DRIVER
```

### 8.5 TI MSPM0 构建

优先使用项目已有 SysConfig 输出：

```text
Debug/ti_msp_dl_config.c
Debug/ti_msp_dl_config.h
Debug/device_linker.cmd
Debug/device.cmd.genlibs
```

不要第一版尝试重新运行 SysConfig。

TI 编译输入：

```text
项目 C 文件
Debug/ti_msp_dl_config.c
SDK startup_mspm0*_ticlang.c
driverlib.a
device_linker.cmd
device.cmd.genlibs
```

输出：

```text
codex_build/build-ticlang/<Project>.out
codex_build/build-ticlang/<Project>.hex
codex_build/build-ticlang/<Project>.bin
```

## 9. 烧录策略

### 9.1 STM32 OpenOCD

STM32F1：

```sh
openocd -f interface/stlink.cfg \
        -f target/stm32f1x.cfg \
        -c "adapter speed 4000" \
        -c "program firmware.elf verify reset exit"
```

STM32F4：

```sh
openocd -f interface/stlink.cfg \
        -f target/stm32f4x.cfg \
        -c "adapter speed 4000" \
        -c "program firmware.elf verify reset exit"
```

OpenOCD 失败关键词：

```text
Error:
error:
failed
Failed
unable to
Unable to
No device
no device
timed out
Target not examined
verification failed
```

OpenOCD 成功关键词：

```text
verified
shutdown command invoked
```

### 9.2 TI J-Link

J-Link flash script：

```text
connect
r
h
loadfile "<absolute path to hex>"
r
g
exit
```

注意：路径必须加引号，支持空格和中文路径。

执行：

```sh
JLinkExe -NoGui 1 -Device MSPM0G3507 -If SWD -Speed 4000 -CommandFile jlink_flash.jlink
```

成功判断：

```text
DAP initialized successfully
O.K.
Flash download
```

失败判断：

```text
Failed to initialize DAP
Could not connect to the target device
Target connection not established
Can not attach to CPU
returned with error code
```

## 10. ScriptRunner 设计

Swift 使用 `Process` 执行脚本。

### 10.1 资源脚本定位

如果使用 Swift Package，脚本放在：

```text
Sources/SuperFlash/Resources/scripts/
```

通过：

```swift
Bundle.module.url(forResource: "stm32_build_flash", withExtension: "py", subdirectory: "scripts")
Bundle.module.url(forResource: "ti_mspm0_build_flash", withExtension: "py", subdirectory: "scripts")
```

获取路径。

注意：`Bundle.module` 只在 Swift Package target 中可用。如果后续改为 Xcode App target，则改用：

```swift
Bundle.main.url(forResource: "stm32_build_flash", withExtension: "py", subdirectory: "scripts")
```

第一版建议直接用 `/usr/bin/python3 script.py ...`，脚本本身不一定需要 executable bit。

### 10.2 环境变量

运行外部命令时需要补全 PATH，避免 GUI App 环境没有 Homebrew 路径。

推荐：

```swift
var env = ProcessInfo.processInfo.environment
env["PATH"] = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin"
].joined(separator: ":")
process.environment = env
```

TI/J-Link 等特殊路径由后端脚本自己扫描。

示例：

```swift
final class ScriptRunner: ObservableObject {
    @Published var state: RunState = .idle
    @Published var logs: [LogEntry] = []

    private var process: Process?

    func run(script: URL, project: URL, action: BuildAction) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            script.path,
            project.path,
            "--action",
            action.cliValue
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.finish(exitCode: process.terminationStatus)
            }
        }

        self.process = process
        try? process.run()
    }

    func cancel() {
        process?.terminate()
        state = .cancelled
    }
}
```

路径必须用 `arguments` 传，不要拼 shell 字符串，避免中文路径和空格路径问题。

## 11. LogParser 设计

实时解析日志，更新 UI 状态。

### 11.1 通用状态关键词

Building：

```text
arm-none-eabi-gcc
tiarmclang
Compiling
Linking
```

Flashing：

```text
openocd
J-Link Commander
Programming flash
Downloading file
```

Success：

```text
O.K.
verified
IPSR = 000 (NoException)
DAP initialized successfully
```

Failure：

```text
error:
Error:
failed
Failed
Could not connect
Target connection not established
No such file
command not found
```

### 11.2 诊断输出

`LogParser` 输出 `DiagnosticIssue`：

```swift
struct DiagnosticIssue {
    var title: String
    var detail: String
    var suggestion: String
}
```

示例：

```text
标题：未找到 ARM GCC
详情：arm-none-eabi-gcc 不在 PATH 和常见目录中。
建议：确认 /opt/homebrew/bin/arm-none-eabi-gcc 是否存在。
```

```text
标题：J-Link 能看到目标电压但无法连接 DAP
详情：VTref=3.300V，但 Failed to initialize DAP。
建议：检查 SWDIO/SWCLK/GND/NRST 接线和目标板状态。
```

## 12. 设置页

第一版设置项：

```text
ARM GCC 路径
OpenOCD 路径
TI Arm Clang 路径
MSPM0 SDK 路径
JLinkExe 路径
OpenOCD adapter speed
J-Link speed
是否自动打开报告
是否保存最近项目
```

默认自动检测，用户可以覆盖。

存储：

```swift
UserDefaults
```

或者：

```text
~/Library/Application Support/SuperFlash/config.json
```

## 13. 报告文件

每次运行生成 Markdown 报告。

STM32：

```text
codex_build/STM32_BUILD_FLASH_REPORT.md
```

TI：

```text
codex_build/TI_BUILD_FLASH_REPORT.md
```

报告内容：

```text
项目路径
时间
项目类型
芯片
工程类型
工具链路径
构建命令
烧录命令
产物路径
完整日志摘要
成功/失败结论
错误诊断
下一步提示
```

## 14. 错误场景处理

### 14.1 缺 ARM GCC

显示：

```text
未找到 arm-none-eabi-gcc。
已检查：
/opt/homebrew/bin
/usr/local/bin
~/arm-gcc-toolchain/bin
PATH
```

### 14.2 缺 OpenOCD

显示：

```text
未找到 OpenOCD。
STM32 烧录需要 OpenOCD + ST-Link。
```

### 14.3 ST-Link 未连接

显示：

```text
OpenOCD 无法连接 ST-Link 或目标板。
请检查：
1. ST-Link 是否插入
2. 目标板是否供电
3. SWDIO/SWCLK/GND/NRST 是否接对
4. 是否有其他 OpenOCD 进程占用
```

### 14.4 J-Link DAP 失败

显示：

```text
J-Link 能检测到目标电压，但无法初始化 DAP。
这通常不是编译问题，而是 SWD 连接或目标板状态问题。
```

### 14.5 Keil 工程解析不完整

显示：

```text
检测到 Keil 工程，但部分源文件或 include path 不存在。
已跳过不存在路径，请检查 codex_build/ 报告。
```

### 14.6 裸文件夹缺 linker script

显示：

```text
未找到 linker script。
已根据检测到的芯片生成临时 linker script。
请确认 Flash/RAM 大小是否正确。
```

## 15. 第一版开发步骤

### 15.0 真实测试项目

实现过程中优先使用这些本机项目做验收：

STM32F4：

```text
/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/f4模块
```

预期：

- 识别为 STM32。
- 识别芯片为 `STM32F407ZG`。
- 识别系列为 `f4`。
- 识别到已有 `Makefile`。
- 构建时复用已有 Makefile。
- 找到产物 `build/firmware.elf`。

TI MSPM0：

```text
/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/Test
/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/Test 2
```

预期：

- 识别为 TI MSPM0。
- 识别芯片为 `MSPM0G3507`。
- 识别到 CCS/SysConfig 输出。
- 路径带空格的 `Test 2` 必须能正常处理。

后端脚本单独验收命令：

```sh
python3 ~/.claude/skills/stm32-build-flash/scripts/stm32_build_flash.py "/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/f4模块" --action build

python3 ~/.claude/skills/ti-build-flash/scripts/ti_mspm0_build_flash.py "/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/Test" --action build

python3 ~/.claude/skills/ti-build-flash/scripts/ti_mspm0_build_flash.py "/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/Test 2" --action build
```

App 集成验收：

- 从 UI 选择上述项目。
- UI 展示的识别结果与预期一致。
- 点击“仅编译”后实时日志滚动。
- 构建结束后状态变为成功。
- “打开产物目录”能打开对应 `codex_build` 或 `build` 目录。
- 中文路径和空格路径不报错。

### 阶段 1：SwiftUI 壳

1. 创建 macOS SwiftUI App。
2. 如果使用 Swift Package 原型，先实现 `Package.swift` 和 `swift run SuperFlash`。
3. 如果使用 Xcode App target，关闭 App Sandbox。
4. 实现 `ContentView` 基础布局。
5. 实现 `NSOpenPanel` 选择目录。
6. 实现实时日志窗口。
7. 实现 `Process` 执行 `/bin/ls` 测试。

验收：

- `swift build` 成功。
- `swift run SuperFlash` 能打开窗口。
- 能选择项目目录。
- 能执行命令。
- 日志能实时显示。
- 能取消命令。

### 阶段 2：项目识别

1. 实现 `ProjectDetector`。
2. 支持 STM32F1/F4 识别。
3. 支持 TI MSPM0 识别。
4. 支持 Keil/裸文件夹/Makefile/CCS 识别。
5. UI 展示识别结果。

验收：

- 选择 `f4模块` 能识别 STM32F407ZG。
- 选择 TI MSPM0 项目能识别 MSPM0G3507。
- 未知项目显示 unknown，不崩溃。

### 阶段 3：环境检查

1. 实现 ARM GCC 检查。
2. 实现 OpenOCD 检查。
3. 实现 TI Arm Clang 检查。
4. 实现 MSPM0 SDK 检查。
5. 实现 JLinkExe 检查。
6. UI 展示依赖状态。

验收：

- 能显示每个工具路径。
- 缺工具时有明确提示。

### 阶段 4：接入后端脚本

1. 将 `stm32_build_flash.py` 放入 App resources。
2. 将 `ti_mspm0_build_flash.py` 放入 App resources。
3. 根据项目类型选择脚本。
4. 实现 `仅编译`。
5. 实现 `编译并烧录`。
6. 实现 `仅烧录`。
7. 实现 `验证连接`。

验收：

- STM32 项目能触发 STM32 脚本。
- TI 项目能触发 TI 脚本。
- 日志实时显示。
- 失败能显示诊断。

### 阶段 5：报告和产物

1. 自动读取报告路径。
2. 实现打开 `codex_build`。
3. 实现复制错误诊断。
4. 实现最近项目列表。
5. 实现设置页。

验收：

- 运行后能打开报告。
- 最近项目能保存。
- 工具链路径能手动覆盖。

## 16. 后端脚本接口约定

STM32：

```sh
python3 stm32_build_flash.py "<project>" --action build
python3 stm32_build_flash.py "<project>" --action flash
python3 stm32_build_flash.py "<project>" --action verify
python3 stm32_build_flash.py "<project>" --action all
```

可选：

```sh
--mcu STM32F407ZG
--target-cfg target/stm32f4x.cfg
--interface-cfg interface/stlink.cfg
--adapter-speed 4000
--force-generated-build
```

TI：

```sh
python3 ti_mspm0_build_flash.py "<project>" --action build
python3 ti_mspm0_build_flash.py "<project>" --action flash
python3 ti_mspm0_build_flash.py "<project>" --action verify
python3 ti_mspm0_build_flash.py "<project>" --action all
```

可选：

```sh
--device MSPM0G3507
--sdk-root /Applications/ti/mspm0_sdk_2_04_00_06
--cgt-root /Applications/ti/ccstheia151/ccs/tools/compiler/ti-cgt-armllvm_4.0.0.LTS
--jlink /Users/lcq/SEGGER_JLink_V950/JLinkExe
--speed 4000
```

## 17. Claude 实现提示词

```text
请在 /Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash 中实现一个 macOS 原生 SwiftUI App，名字 SuperFlash。请严格按照 TECHNICAL_ROADMAP.md 实现。

目标：选择嵌入式项目后一键编译烧录，支持 STM32F1、STM32F4、TI MSPM0。

约束：
1. 软件只给我自己用，不需要 App Store，不需要沙盒。
2. 只检测本机已有工具链，不自动安装。
3. STM32 使用 ST-Link + OpenOCD。
4. TI MSPM0 使用 J-Link + TI Arm Clang + MSPM0 SDK。
5. 优先适配 Keil 工程迁移、裸文件夹项目、已有 Makefile 项目。
6. 所有生成内容放项目的 codex_build/。
7. 路径必须支持中文和空格。
8. 命令执行用 Process + Pipe 实时显示日志。
9. 成功失败不能只看退出码，要解析 OpenOCD/J-Link 输出。

开发顺序：
第一步先搭 SwiftUI App 壳、项目选择、日志窗口、Process 执行测试命令。
第二步做 ProjectDetector。
第三步做 EnvironmentChecker。
第四步接入后端脚本执行 build/flash/verify。
第五步做报告、最近项目、设置页。

不要一上来做复杂 UI，先保证端到端可用。
```
