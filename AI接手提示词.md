# SuperFlash AI 接手提示词

## 项目简介

SuperFlash 是 macOS 原生 SwiftUI 桌面应用，用于 STM32/TI MSPM0 嵌入式项目的编译和烧录。

**技术栈**: Swift 6 + Python 3
**构建**: `swift build -c release`
**部署**: `cp .build/release/SuperFlash /Applications/SuperFlash.app/Contents/MacOS/SuperFlash && codesign --force --deep --sign - /Applications/SuperFlash.app`
**代码位置**: `/Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash`
**GitHub**: `https://github.com/lcqxidian/SuperFlash`

## 你需要读取的文档

请先完整阅读以下文件（按顺序）：

1. `/Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash/PROJECT_DOCUMENTATION.md` — **完整工程文档**，包含：
   - STM32 F4 烧录原理（逐行注释）
   - TI MSPM0 烧录原理（逐行注释）
   - Swift 应用层架构
   - CLI 接口
   - 已知问题清单

2. `/Users/lcq/Desktop/ORICO/WorkSpace/SuperFlash/API文档.md` — CLI 命令行接口用法

3. 核心代码文件（根据需要阅读）：
   - `Sources/SuperFlash/Resources/scripts/ti_mspm0_build_flash.py` — **TI MSPM0 构建烧录脚本**（重点！问题在这）
   - `Sources/SuperFlash/Resources/scripts/stm32_build_flash.py` — STM32 构建烧录脚本
   - `Sources/SuperFlash/App/AppState.swift` — 中心状态管理
   - `Sources/SuperFlash/Services/ScriptRunner.swift` — 进程管理器
   - `Sources/SuperFlash/CLI/CLIHandler.swift` — 命令行接口
   - `Sources/SuperFlash/UI/NewProjectView.swift` — 新项目创建

## 需要解决的核心问题

### 现象

TI MSPM0G3507 芯片通过 **SAM-ICE**（SEGGER J-Link ARM-OB STM32 固件，2012 年出厂，序列号 20090928）烧录时：

- **芯片断电后再上电的第一次烧录**：100% 失败
- **不断电的后续烧录**：100% 成功
- 错误信息：
  - JLinkExe: `Error: Failed to initialize DAP. Can not attach to CPU.`
  - DSLite: `ERROR in JLINKARM_Open: Cannot connect to the probe/programmer.` 或 `Error connecting to the target: Could not connect to target.`

### 规律

- 芯片刚上电时，DAP（Debug Access Port，ARM 调试端口）处于某种初始状态
- SAM-ICE 无法在这个初始状态下连接 DAP
- 一旦 DSLite 成功连接过一次（比如之前成功烧录过），芯片进入"热"状态，后续烧录都正常
- 如果芯片完全断电（拔电源线），DAP 回到初始状态，下次烧录又失败
- 跟 SAM-ICE USB 是否被虚拟机占用无关（已确认不是这个原因）

### 已经尝试过的方案（都不行）

1. **JLinkExe 先连接，再 DSLite 烧录** — JLinkExe 自己也连不上 DAP
2. **降低 SWD 速度到 100kHz** — 无效
3. **替换 DSLite 的 libjlinkarm 库为 JLinkExe 9.50 版本** — 能识别探头但 DAP 初始化仍失败
4. **加 3 次重试，每次间隔 3 秒** — 无效（已回退）
5. **JLinkExe 暖机（先用 JLinkExe 连接再断开）** — 无效（已回退）
6. **换 ccxml 配置（XDS110 vs J-Link 驱动）** — 不影响问题（ccxml 只改了 DSLite 能识别 SAM-ICE）

### 可能的方向

请思考以下方向（不要局限于此）：

- **MSPM0 DAP 初始化时序**：芯片上电后需要特定 SWD 序列才能解锁 DAP
- **SAM-ICE 的 reset 引脚**：目前没有连接 nRST。如果通过硬复位强制芯片进入调试模式，DAP 可能可访问
- **OpenOCD 替代**：是否可以用 OpenOCD 代替 DSLite 来烧录 MSPM0？（OpenOCD 支持 CMSIS-DAP 但不支持 SAM-ICE 的 J-Link 协议）
- **pyocd**：开源的 Python 烧录工具，支持 CMSIS-DAP 和 J-Link
- **芯片安全位**：MSPM0 可能有安全锁定位，断电后需要先擦除才能连接
- **DSLite/MSPM0 GEL 脚本**：修改 `/Applications/ti/ccstheia151/ccs/ccs_base/emulation/gel/mspm0g3507.gel` 中的 `OnPreTargetConnect()` 函数来调整连接时序

## 代码修改注意事项

1. **未经用户本人明确允许，禁止执行任何 Git 写操作**，包括但不限于 `git add`、`git commit`、创建或切换分支、回退、rebase、merge、push；仅允许使用 `git status`、`git diff`、`git log` 等只读命令检查状态
2. **只改必要的代码**，不动无关逻辑
3. **如果要改 Python 脚本**：修改后需要 `swift build -c release` 重新构建（脚本是 Resource，会自动打包），然后部署 `cp` 到 app bundle
4. **如果要改 Swift 代码**：同样 `swift build` + 部署
5. **每次修改后必须测试**：用 CLI 命令测试
   ```bash
   # 先断掉 MSPM0 板子的电，再接上
   # 然后测试
   /Applications/SuperFlash.app/Contents/MacOS/SuperFlash build-flash "/Users/lcq/Desktop/ORICO/电赛/临时项目/Test4"
   ```
6. **如果发现改错了，立即回退**
7. **TI CCS Theia 安装位置**: `/Applications/ti/ccstheia151/`
8. **MSPM0 SDK 位置**: `/Applications/ti/mspm0_sdk_2_04_00_06/`
9. **JLinkExe 位置**: `/Users/lcq/SEGGER_JLink_V950/JLinkExe`

## 硬件环境

- **电脑**: Mac17,9 (Apple Silicon), macOS 26.5.1
- **调试器**: SAM-ICE (Atmel, S/N 20090928), J-Link ARM-OB STM32 固件 v7.00 (2012)
- **目标芯片**: TI MSPM0G3507 (Cortex-M0+), LaunchPad 核心板
- **连接**: SWD (SWCLK + SWDIO + GND), 无 RESET 引脚连接
- **烧录器软件**:
  - SEGGER JLinkExe V9.50 (能识别 SAM-ICE，但无法初始化 MSPM0 DAP)
  - TI DSLite 12.8.0.3529 (通过 ccxml 驱动 SAM-ICE，偶尔能连上)
