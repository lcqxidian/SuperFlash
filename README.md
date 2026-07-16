# SuperFlash

SuperFlash 是一款面向 macOS 的 STM32 与 TI MSPM0 编译、烧录和基础运行验证工具。应用使用 SwiftUI 提供图形界面，实际构建和烧录由应用内置的 Python 脚本调用本机工具链完成。

> 本文既是新用户安装手册，也是交给 Codex 的自动配置说明。新用户可以把本仓库链接和文末的“Codex 一键接手提示词”一起发给 Codex，让它检查电脑、安装缺失依赖、配置 SuperFlash 并完成首次验证。

仓库地址：<https://github.com/lcqxidian/SuperFlash>

## 0. 分享链接之前：仓库当前是 Private

截至 2026-07-16，GitHub 仓库 `lcqxidian/SuperFlash` 的可见性是 **PRIVATE**。未被授权的用户只打开链接会看到 404，并不能下载 `SuperFlash.dmg` 或阅读本文。

维护者在分享前必须选择一种方式：

1. 在 GitHub 仓库设置中邀请对方成为 collaborator；
2. 将仓库改为 public，并在操作前检查源码、历史提交和大文件中没有密钥或隐私信息；
3. 保持 private，但单独通过可信渠道发送 DMG 和这份 README；
4. 建立 GitHub Release，只发布准备公开的安装包和校验值。

如果使用私有仓库，接收方需要先登录已获得授权的 GitHub 账号。Codex 可以检查：

```bash
gh auth status
gh repo view lcqxidian/SuperFlash --json nameWithOwner,visibility,url
gh repo clone lcqxidian/SuperFlash
```

如果 `gh repo view` 返回 404 或 `Could not resolve to a Repository`，先处理 GitHub 访问权限，不要把它误判为 Git、网络或 SuperFlash 安装失败。

> 改变仓库可见性、邀请协作者、创建 Release 都会改变外部访问状态，Codex 必须先获得仓库所有者明确许可。

## 1. 使用前先确认

### 1.1 当前支持范围

| 项目 | 当前状态 |
|---|---|
| Mac 处理器 | **Apple Silicon（arm64）** |
| 最低系统 | macOS 14.0 |
| Intel Mac | 当前 GitHub 中的 DMG **不能直接运行**；需修改构建脚本并自行编译 x86_64 或 universal 版本 |
| STM32 | 构建脚本可识别多个 STM32 系列；仓库内完整附带的是 STM32F4 CMSIS/StdPeriph 资源和 STM32F1 CMSIS 资源 |
| TI | 主要验证目标为 MSPM0G3507，支持 CCS/SysConfig 项目结构 |
| 调试器 | ST-Link、XDS110、通用 SEGGER J-Link；老 SAM-ICE/J-Link ARM-OB 有专门兼容流程 |

先在终端检查：

```bash
uname -m
sw_vers -productVersion
```

预期第一条输出 `arm64`，macOS 主版本不低于 14。若输出 `x86_64`，不要安装当前 DMG。

### 1.2 GitHub 仓库里已经有什么

从 GitHub 克隆或下载后，可以得到：

- `SuperFlash.dmg`：已经构建的 Apple Silicon 应用安装镜像；
- `Sources/SuperFlash/`：完整 SwiftUI 源码；
- `Sources/SuperFlash/Resources/scripts/`：STM32 与 TI MSPM0 构建烧录脚本；
- `Sources/SuperFlash/Resources/CMSIS*` 和 `FWLib/`：随应用打包的部分 STM32 头文件与标准外设库；
- `tools/deploy_superflash_app.sh`：从源码构建并部署到 `/Applications` 的脚本；
- `PROJECT_DOCUMENTATION.md`：架构、烧录原理、历史修复和已知风险；
- `AI接手提示词.md`：开发维护时使用的项目接手约束；
- `API文档.md`、`新建项目须知.md`、`TECHNICAL_ROADMAP.md`：补充技术资料。

仓库**不包含**以下第三方软件，因为它们体积较大或有各自的许可协议：

- Apple Command Line Tools / Xcode；
- GNU Arm Embedded Toolchain；
- OpenOCD、STM32CubeProgrammer；
- TI Code Composer Studio、TI Arm Clang、MSPM0 SDK、DSLite；
- SEGGER J-Link Software；
- 调试器硬件和目标板驱动固件。

### 1.3 不需要安装 Python 第三方库

SuperFlash 的两个 Python 脚本只使用 Python 标准库，不需要 `pip install`，也没有 `requirements.txt`。

但当前应用明确调用：

```text
/usr/bin/python3
```

所以必须确保该路径存在。通常安装 Apple Command Line Tools 后即可使用：

```bash
xcode-select --install
/usr/bin/python3 --version
```

如果电脑只有 Homebrew Python，而 `/usr/bin/python3` 不存在，当前应用仍无法调用它。此时应优先安装 Apple Command Line Tools；不要仅靠创建系统目录软链接解决。

### 1.4 安装包完整性与版本记录

当前仓库没有自动生成 Release 校验清单。维护者每次更新 DMG 后，建议同时公布提交号和 SHA-256：

```bash
git rev-parse HEAD
shasum -a 256 SuperFlash.dmg
```

接收方下载后再次执行：

```bash
shasum -a 256 ~/Downloads/SuperFlash.dmg
```

两边 SHA-256 必须完全一致。若不一致，不要清除 Gatekeeper 隔离属性，也不要运行应用；应重新下载并确认发布来源。

由于当前 DMG 没有 Developer ID 公证，SHA-256、Git 提交号和可信传输渠道尤其重要。

## 2. 最快安装方式：使用 DMG

### 2.1 下载与复制

1. 打开 GitHub 仓库。
2. 下载根目录中的 `SuperFlash.dmg`，或者克隆仓库后直接打开该文件。
3. 双击挂载 DMG。
4. 将 `SuperFlash.app` 复制到 `/Applications`。

也可以由 Codex 在本地仓库中执行：

```bash
hdiutil attach ./SuperFlash.dmg -nobrowse
cp -R /Volumes/SuperFlash/SuperFlash.app /Applications/SuperFlash.app
hdiutil detach /Volumes/SuperFlash
```

挂载卷名称如果不是 `SuperFlash`，应以 `hdiutil attach` 的实际输出为准，不要盲目复制命令。

### 2.2 首次打开与 macOS 安全提示

当前 DMG 内应用使用临时 ad-hoc 签名，没有 Apple Developer ID 公证。因此别人的 Mac 可能提示“无法验证开发者”或阻止首次打开。

推荐按以下顺序处理：

1. 在 Finder 中右键 `SuperFlash.app`，选择“打开”；
2. 如果仍被拦截，进入“系统设置 → 隐私与安全性”，确认应用来源后选择“仍要打开”；
3. 只有在确认 DMG 来自本仓库且文件未被替换时，才让 Codex 执行：

```bash
xattr -dr com.apple.quarantine /Applications/SuperFlash.app
```

不要对不明来源应用批量清除隔离属性。

### 2.3 验证应用本体

```bash
test -x /Applications/SuperFlash.app/Contents/MacOS/SuperFlash
file /Applications/SuperFlash.app/Contents/MacOS/SuperFlash
codesign --verify --deep --strict /Applications/SuperFlash.app
```

当前发布包的可执行文件应显示 `Mach-O 64-bit executable arm64`。

## 3. 依赖不是全部都要装

新用户只应安装自己目标平台需要的工具。依赖关系如下：

| 用途 | 必需依赖 | 按硬件选择 |
|---|---|---|
| 只打开 SuperFlash | macOS 14+、`/usr/bin/python3` | 无 |
| STM32 仅编译 | GNU Arm Embedded Toolchain | 项目自带或仓库附带的 CMSIS/HAL/StdPeriph 资源 |
| STM32 编译并烧录 | GNU Arm Embedded Toolchain + OpenOCD | ST-Link；STM32CubeProgrammer 可作为备用烧录器 |
| TI MSPM0 仅编译 | TI Arm Clang + MSPM0 SDK | 最简单的来源是安装 TI Code Composer Studio 和 MSPM0 SDK |
| TI + XDS110 | TI Arm Clang + MSPM0 SDK + CCS/DSLite | XDS110 |
| TI + 通用 J-Link | TI Arm Clang + MSPM0 SDK + SEGGER J-Link Software | 对应 J-Link 硬件 |
| TI + 老 SAM-ICE/J-Link ARM-OB | TI Arm Clang + MSPM0 SDK + CCS/DSLite + SEGGER J-Link Software | 两套软件都必须安装 |

### 3.1 三种最小安装方案

#### 方案 A：STM32 + ST-Link

只安装：

1. Apple Command Line Tools；
2. SuperFlash；
3. 完整 GNU Arm Embedded Toolchain；
4. OpenOCD；
5. 项目需要但仓库未附带的 HAL/LL/CMSIS 芯片包。

不需要安装 CCS、MSPM0 SDK 或 J-Link Software。

#### 方案 B：MSPM0 LaunchPad + XDS110

只安装：

1. Apple Command Line Tools；
2. SuperFlash；
3. TI Code Composer Studio；
4. MSPM0 SDK。

CCS 提供 TI Arm Clang、DSLite 和 XDS110 工具。没有使用 J-Link 时，不需要 SEGGER 软件。

#### 方案 C：MSPM0 + J-Link/SAM-ICE

安装：

1. Apple Command Line Tools；
2. SuperFlash；
3. TI Code Composer Studio；
4. MSPM0 SDK；
5. SEGGER J-Link Software。

普通 J-Link 有时可直接使用 JLinkExe；老 SAM-ICE 必须保留 CCS/DSLite，因为它负责冷启动阶段唤醒 DAP。

### 3.2 依赖安装前应记录的信息

让新用户或 Codex 先填写：

```text
Mac 型号/处理器：
macOS 版本：
目标平台：STM32 / TI MSPM0
芯片完整型号：
调试器品牌和具体型号：
调试接口：SWD / JTAG
目标板是否独立供电：
工程绝对路径：
只需编译还是需要真实烧录：
```

芯片和调试器不明确时，不应猜测并安装整套厂商软件。可以先查看工程 `.ioc`、`.uvprojx`、`.ccxml`、`.syscfg`、启动文件和芯片丝印。

## 4. 公共基础环境

### 4.1 Apple Command Line Tools

建议所有新用户先安装：

```bash
xcode-select --install
```

安装后检查：

```bash
xcode-select -p
/usr/bin/python3 --version
git --version
```

若用户只使用 DMG，不需要完整 Xcode；如果需要从源码构建 SuperFlash，则需要支持 Swift 6 的 Xcode/Swift 工具链。

### 4.2 Homebrew（STM32/OpenOCD 路径常用）

如尚未安装 Homebrew，应从官方站点 <https://brew.sh/> 获取安装命令。安装后：

```bash
brew --version
```

Apple Silicon 默认命令目录通常是 `/opt/homebrew/bin`；SuperFlash 会自动搜索该目录。

### 4.3 Codex 使用的只读环境体检

下面脚本不会安装软件、修改配置或烧录目标板，可以作为新 Mac 的第一步：

```bash
echo '=== Mac ==='
uname -m
sw_vers

echo '=== Apple tools / Python ==='
xcode-select -p 2>&1 || true
/usr/bin/python3 --version 2>&1 || true
git --version 2>&1 || true
swift --version 2>&1 || true

echo '=== SuperFlash ==='
test -d /Applications/SuperFlash.app && echo 'SuperFlash.app: installed' || echo 'SuperFlash.app: missing'
test -x /Applications/SuperFlash.app/Contents/MacOS/SuperFlash && \
  file /Applications/SuperFlash.app/Contents/MacOS/SuperFlash || true

echo '=== STM32 tools ==='
command -v arm-none-eabi-gcc || true
command -v arm-none-eabi-objcopy || true
command -v arm-none-eabi-size || true
command -v openocd || true
find "$HOME/arm-gcc-toolchain" -maxdepth 2 -type f -name arm-none-eabi-gcc -perm -111 2>/dev/null || true

echo '=== TI tools ==='
find /Applications/ti -type f \( -name tiarmclang -o -name DSLite -o -name xdsdfu \) -perm -111 2>/dev/null || true
find /Applications/ti -maxdepth 1 -type d -name 'mspm0_sdk_*' 2>/dev/null || true

echo '=== SEGGER ==='
command -v JLinkExe || true
find /Applications/SEGGER "$HOME" -maxdepth 3 -type f -name JLinkExe -perm -111 2>/dev/null || true

echo '=== USB debug probes ==='
system_profiler SPUSBDataType | grep -i -A6 -B2 \
  'ST-LINK\|STLink\|STMicroelectronics\|XDS110\|J-Link\|SEGGER\|SAM-ICE' || true
```

Codex 应把输出整理成“已满足 / 缺失 / 与当前任务无关”三类，再提出安装动作。不要因为 TI 工具缺失就阻止只做 STM32 的用户，也不要因为 OpenOCD 缺失就阻止只做 TI 的用户。

## 5. STM32 环境配置

如果新用户只使用 TI MSPM0，可跳过本章。

### 5.1 安装 GNU Arm Embedded Toolchain

SuperFlash 需要至少包含以下程序：

```text
arm-none-eabi-gcc
arm-none-eabi-objcopy
arm-none-eabi-size
```

优先建议使用 Arm 官方提供、包含 newlib 的 `arm-none-eabi` 工具链：

<https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads>

当前脚本会优先搜索：

```text
~/arm-gcc-toolchain/bin/arm-none-eabi-gcc
/opt/homebrew/bin/arm-none-eabi-gcc
/usr/local/bin/arm-none-eabi-gcc
PATH 中的 arm-none-eabi-gcc
```

推荐将官方工具链解压或安装后整理为：

```text
~/arm-gcc-toolchain/bin/arm-none-eabi-gcc
```

验证工具链不能只看 `--version`，还应确认标准头文件和链接库完整：

```bash
~/arm-gcc-toolchain/bin/arm-none-eabi-gcc --version
printf '#include <stdint.h>\nint main(void){return 0;}\n' >/tmp/superflash_gcc_test.c
~/arm-gcc-toolchain/bin/arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb \
  --specs=nosys.specs /tmp/superflash_gcc_test.c -o /tmp/superflash_gcc_test.elf
rm -f /tmp/superflash_gcc_test.c /tmp/superflash_gcc_test.elf
```

如果出现 `stdint.h`、`libc.a`、`nosys.specs` 缺失，说明安装的是不完整工具链。不要只修改 include 路径掩盖问题，应改用带 newlib 的完整发行包。

### 5.2 安装 OpenOCD

使用 ST-Link 烧录时推荐：

```bash
brew install openocd
openocd --version
```

OpenOCD 官方站点：<https://openocd.org/>

SuperFlash 自动搜索 `/opt/homebrew/bin/openocd`、`/usr/local/bin/openocd` 和 `PATH`。

### 5.3 可选：STM32CubeProgrammer

当 OpenOCD 不可用时，烧录脚本可以回退到 `STM32_Programmer_CLI`。官方下载入口：

<https://www.st.com/en/development-tools/stm32cubeprog.html>

脚本会搜索常见的 `/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/` 安装位置。

### 5.4 检查 ST-Link

接好目标板电源、SWDIO、SWCLK、GND，必要时连接 NRST，然后检查 USB：

```bash
system_profiler SPUSBDataType | grep -i -A6 -B2 'ST-LINK\|STLink\|STMicroelectronics'
```

如果完全没有输出，先处理 USB 线、电源、转接器和调试器固件，不要反复重装编译器。

## 6. TI MSPM0 环境配置

如果新用户只使用 STM32，可跳过本章。

### 6.1 安装 TI Code Composer Studio

官方下载入口：<https://www.ti.com/tool/CCSTUDIO>

安装 macOS 版本，并保留 TI 默认目录。SuperFlash 会自动搜索：

```text
/Applications/ti/ccstheia*/ccs/tools/compiler/ti-cgt-armllvm_*/bin/tiarmclang
/Applications/ti/ccstheia*/ccs/ccs_base/DebugServer/bin/DSLite
/Applications/ti/ccs*/...
```

不同版本目录名可以不同，只要目录仍位于 `/Applications/ti` 且保持 TI 默认结构，通常不需要手动配置。

检查：

```bash
find /Applications/ti -type f -name tiarmclang -perm -111 2>/dev/null
find /Applications/ti -type f -name DSLite -perm -111 2>/dev/null
```

### 6.2 安装 MSPM0 SDK

官方下载入口：<https://www.ti.com/tool/MSPM0-SDK>

推荐安装到 TI 默认位置：

```text
/Applications/ti/mspm0_sdk_<版本号>
```

SuperFlash 会检查至少存在：

```text
source/ti/devices/msp/m0p/startup_system_files/ticlang
source/ti/driverlib/lib/ticlang/m0p
```

检查：

```bash
find /Applications/ti -maxdepth 1 -type d -name 'mspm0_sdk_*' -print
```

### 6.3 使用 XDS110

XDS110 通常随 TI LaunchPad 使用。安装 CCS 后，SuperFlash 会使用 TI 自带的 `xdsdfu` 和 DSLite 检测、下载。

检查：

```bash
XDSDFU=$(find /Applications/ti -type f -name xdsdfu -perm -111 2>/dev/null | head -n 1)
test -n "$XDSDFU" && "$XDSDFU" -e
```

### 6.4 使用 SEGGER J-Link 或 SAM-ICE

安装官方 J-Link Software and Documentation Pack：

<https://www.segger.com/downloads/jlink/>

SEGGER 提供 Apple Silicon、Intel 和 Universal 等 macOS 安装包，应选择与用户 Mac 匹配的版本。SuperFlash 会搜索：

```text
/Applications/SEGGER/JLink/JLinkExe
~/SEGGER_JLink_V950/JLinkExe
/usr/local/bin/JLinkExe
/opt/homebrew/bin/JLinkExe
PATH 中的 JLinkExe
```

检查软件和 USB 探针：

```bash
find /Applications/SEGGER "$HOME" -maxdepth 3 -type f -name JLinkExe -perm -111 2>/dev/null
system_profiler SPUSBDataType | grep -i -A6 -B2 'J-Link\|SEGGER\|SAM-ICE'
```

老 SAM-ICE/J-Link ARM-OB 与 MSPM0 冷启动连接不稳定。SuperFlash 当前采用：

```text
DSLite 建立连接并唤醒 DAP
→ J-Link loadfile 完整 Program & Verify
→ 设备级复位
→ 读取寄存器确认 IPSR = 000 (NoException)
→ go 运行
```

因此老 SAM-ICE 用户必须同时安装 CCS/DSLite 和 SEGGER J-Link Software。日志中 DSLite 偶尔出现 `Trouble Writing Register PC`，不能单独据此判断失败；只有后续 J-Link `program/reset/validation: OK` 才代表最终成功。

## 7. 在 SuperFlash 中配置路径

启动应用后打开“设置”，优先保持路径为空，让应用自动检测。只有自动检测失败时再填写完整绝对路径。

可配置项目包括：

- ARM GCC：填写 `arm-none-eabi-gcc` 可执行文件；
- OpenOCD：填写 `openocd` 可执行文件；
- TI Arm Clang：可填写工具链根目录、`bin` 目录或 `tiarmclang` 文件；
- MSPM0 SDK：填写 `mspm0_sdk_<版本号>` 根目录；
- JLinkExe：填写 `JLinkExe` 可执行文件。

示例：

```text
ARM GCC:     /Users/<用户名>/arm-gcc-toolchain/bin/arm-none-eabi-gcc
OpenOCD:     /opt/homebrew/bin/openocd
TI Arm Clang:/Applications/ti/ccstheia<版本>/ccs/tools/compiler/ti-cgt-armllvm_<版本>/bin/tiarmclang
MSPM0 SDK:   /Applications/ti/mspm0_sdk_<版本>
JLinkExe:    /Applications/SEGGER/JLink/JLinkExe
```

不要把开发者电脑上的 `/Users/lcq/...` 路径原样复制给新用户。代码中虽然保留了该路径作为一个兼容候选，但找不到时还会继续搜索标准位置、设置值和 `PATH`。

## 8. 第一次使用

### 8.1 准备工程

STM32 工程最好至少包含以下一种特征：

- `.ioc`；
- `.uvprojx`；
- `startup_stm32*.s`；
- STM32 链接脚本 `.ld`；
- `DRIVE/stm32_mcu`。

TI MSPM0 工程最好包含：

- `targetConfigs/*.ccxml`；
- `ti_msp_dl_config.c/.h`；
- `.syscfg`；
- `device_linker.cmd`；
- CCS 生成的 `Debug/subdir_vars.mk`。

### 8.2 建议的验证顺序

不要第一次就把“编译问题、工具问题和硬件连接问题”混在一起。按顺序执行：

1. 在应用中添加工程；
2. 运行“环境检查”；
3. 执行“仅编译”；
4. 编译成功后连接目标板；
5. 执行“验证连接”；
6. 最后执行“编译并烧录”；
7. 查看项目 `codex_build/` 下的报告。

### 8.3 首次真实烧录前检查表

真实烧录会改变目标板 Flash。执行前逐项确认：

- 工程和芯片型号匹配，不能把 MSPM0G3507 固件写入其他型号，也不能只按系列名猜 STM32 容量；
- 目标板电压与调试器 VTref 兼容；
- GND 共地；
- SWDIO、SWCLK 没有接反；
- NRST 能接时尽量接入，尤其是低功耗、修改 SWD 引脚或上电即异常的程序；
- 调试器固件和桌面软件能识别硬件；
- 没有 CCS、Keil、CubeIDE、OpenOCD 或其他调试会话同时占用探针；
- 已保存用户工程的未提交修改；
- 用户明确允许本次真实烧录。

首次烧录建议先使用最小 LED/串口工程验证链路，再烧录包含电机、功率输出或高电压控制的完整程序。对可能驱动机械结构的固件，应先断开执行器电源或采取安全限位。

### 8.4 使用 CLI 让 Codex 自动测试

安装应用后，Codex 可以直接调用：

```bash
APP=/Applications/SuperFlash.app/Contents/MacOS/SuperFlash

"$APP" build "/绝对路径/项目目录"
"$APP" verify "/绝对路径/项目目录"
"$APP" build-flash "/绝对路径/项目目录"
```

路径应始终加引号。CLI 会自动判断 STM32 或 TI，并调用应用内置脚本。

构建产物与报告位于工程自己的 `codex_build/`：

```text
STM32_BUILD_FLASH_REPORT.md
TI_BUILD_FLASH_REPORT.md
```

这些报告包含工具路径、命令、编译输出、烧录结果和寄存器验证信息，排错时应优先交给 Codex。

### 8.5 首次验收记录模板

Codex 完成后应留下类似记录：

```text
SuperFlash 来源提交：
SuperFlash DMG SHA-256：
Mac 架构和系统：
Python 路径和版本：
目标芯片：
调试器：
编译器路径和版本：
SDK 路径和版本：
烧录工具路径和版本：
build：通过 / 失败
verify：通过 / 失败 / 未连接硬件
build-flash：通过 / 失败 / 未经用户授权
报告路径：
PC/MSP/IPSR 或 OpenOCD Verify 证据：
用户现场确认的 LED/OLED/串口/电机现象：
仍未解决的问题：
```

## 9. 如何判断真正成功

### STM32

不要只看界面颜色。至少确认：

- 编译和链接退出码为 0；
- 生成 `.elf/.hex/.bin`；
- OpenOCD 出现 `Verified OK`，或者 CubeProgrammer 明确报告写入成功；
- reset/run 成功；
- 用户要求的 LED、串口、屏幕或电机现象正常。

### TI MSPM0

至少确认：

- 生成 `.out/.hex/.bin`；
- 通用 J-Link 路径出现 `O.K.` 或 `Program & Verify`；
- 老 SAM-ICE 两阶段路径最终出现 `post-DSLite program/reset/validation: OK`；
- 寄存器中 `IPSR = 000 (NoException)`；
- 最终执行 `go`；
- 用户要求的实际硬件现象正常。

工具验证只能证明 MCU 可连接且处于基本可运行状态，不能代替对 OLED、串口、传感器、电机等业务功能的现场观察。

## 10. 常见问题

### “python3 不存在”

先检查 `/usr/bin/python3`，再安装 Apple Command Line Tools。仅安装 `/opt/homebrew/bin/python3` 不能解决当前应用使用绝对路径的问题。

### “arm-none-eabi-gcc not found”

安装完整 GNU Arm Embedded Toolchain，或在 SuperFlash 设置中填入 `arm-none-eabi-gcc` 的绝对路径。

### 编译器存在，但提示 `stdint.h`、`libc.a` 或 `nosys.specs` 缺失

这是 ARM 工具链不完整，不是用户工程 include 写错。改用包含 newlib 的完整 Arm 官方工具链。

### “openocd not found”

执行 `brew install openocd`，然后确认 `which openocd` 有输出；必要时在设置中填写绝对路径。

### 找不到 ST-Link/J-Link/XDS110

先用 `system_profiler SPUSBDataType` 或厂商工具确认 macOS 能看到 USB 设备，再检查目标板供电、GND、SWDIO、SWCLK、NRST 和 USB 数据线。

### “TI Arm Clang not found”或“MSPM0 SDK not found”

确认软件安装在 `/Applications/ti`，并检查 `tiarmclang`、SDK 的 `source` 目录。非标准位置必须在设置中手动填写。

### DSLite 显示 `Trouble Writing Register PC`，最后却显示完成

老 SAM-ICE 流程中，DSLite 仅负责连接和唤醒。继续看后面的 J-Link 结果；若 `loadfile`、`O.K.`、`IPSR = 000` 和 `go` 均成功，则烧录有效。若 J-Link 最终验证失败，才应按烧录失败处理。

### 应用无法打开

确认 Mac 是 arm64、macOS 14+，然后按本文 Gatekeeper 步骤处理。Intel Mac 不能运行当前 DMG。

### App 能打开但依赖全部显示缺失

GUI 应用的 `PATH` 通常比终端短。SuperFlash 已额外搜索 `/opt/homebrew/bin` 和 `/usr/local/bin`；仍失败时，在设置中填写工具的绝对路径并重新执行环境检查。

## 11. 从源码构建 SuperFlash

仅当 DMG 不适用、需要修改代码或需要重新打包时使用。

```bash
git clone https://github.com/lcqxidian/SuperFlash.git
cd SuperFlash
swift --version
swift build -c release
```

Apple Silicon 上可部署：

```bash
bash tools/deploy_superflash_app.sh
```

注意：

- 脚本会删除并重建 `/Applications/SuperFlash.app`；执行前应获得用户明确同意；
- 脚本当前固定读取 `.build/arm64-apple-macosx/release`，不适用于 Intel Mac；
- 脚本使用 ad-hoc 签名，不等于 Developer ID 签名或 Apple 公证；
- 从源码构建 SuperFlash 需要 Swift 6；使用现成 DMG 不需要自行编译 Swift 源码。

验证：

```bash
codesign --verify --deep --strict /Applications/SuperFlash.app
/Applications/SuperFlash.app/Contents/MacOS/SuperFlash
```

## 12. 更新、重置与卸载

### 12.1 更新应用

1. 先记录当前来源提交和新 DMG SHA-256；
2. 退出 SuperFlash，并确认没有正在运行的 Python、OpenOCD、DSLite 或 JLinkExe 烧录任务；
3. 将新 `SuperFlash.app` 替换到 `/Applications`；
4. 重新执行 `codesign --verify`、环境检查和一个已知工程的“仅编译”；
5. 连接硬件后再做 verify/build-flash 回归。

应用设置存储在 macOS UserDefaults 中，普通覆盖安装通常不会自动清除设置。升级后如果仍引用旧工具路径，应在设置界面重新选择，或按下一节重置。

### 12.2 重置 SuperFlash 设置

优先在应用设置界面修改路径。若应用无法打开或设置损坏，可以先备份再清除应用偏好：

```bash
defaults export com.lcq.SuperFlash "$HOME/Desktop/SuperFlash-settings-backup.plist" 2>/dev/null || true
defaults delete com.lcq.SuperFlash
```

重置后需要重新添加最近工程和自定义工具路径。该操作不删除用户工程，也不删除工程中的 `codex_build/`。

如果只想重新生成某个工程的构建产物，可以在没有构建/烧录任务运行时删除该工程的 `codex_build/`。删除前应保留其中的报告；Codex 必须先获得用户许可，因为这属于文件删除操作。

### 12.3 卸载

退出应用后删除：

```bash
rm -rf /Applications/SuperFlash.app
```

如需同时清除偏好：

```bash
defaults delete com.lcq.SuperFlash 2>/dev/null || true
```

这不会卸载 Xcode、Homebrew、ARM GCC、OpenOCD、CCS、MSPM0 SDK 或 J-Link Software。第三方工具可能被其他嵌入式项目共用，不应由 Codex 顺带删除。

### 12.4 收集问题资料

提交问题时至少提供：

- Mac 架构、macOS 版本；
- SuperFlash 对应 Git 提交和 DMG SHA-256；
- 目标芯片、调试器、接线和供电方式；
- 工程类型和绝对路径是否包含空格/中文；
- 完整控制台日志；
- `codex_build/*_REPORT.md`；
- 工具绝对路径和版本；
- 目标板上实际观察到的现象。

分享报告前检查是否包含本机用户名、工程路径或其他不希望公开的信息。

## 13. 给 Codex 的执行原则

Codex 配置新电脑时必须遵守：

1. 先做只读检查，再决定安装什么；不要一开始就安装所有厂商软件。
2. 先询问或识别 Mac 架构、macOS 版本、目标 MCU、调试器型号和工程路径。
3. 只安装用户当前平台所需依赖：STM32 与 TI 依赖分开。
4. 下载工具链时优先使用 Apple、Arm、ST、TI、SEGGER、Homebrew 官方来源。
5. 不把 `/Users/lcq/...` 硬编码到新用户配置。
6. 不创建指向不存在工具的假软链接，不通过隐藏编译错误制造“环境正常”。
7. 未经用户明确许可，不执行 Git 写操作，包括 `git add`、`commit`、`push`、切换或创建分支。
8. 安装软件、修改 `/Applications`、清除 quarantine、连接后真实烧录前，明确告诉用户将要进行的操作。
9. 构建失败时定位第一个真实编译或链接错误；烧录失败时区分工具退出信息与最终硬件验证结果。
10. 完成后交付依赖清单、实际路径、版本、测试命令、报告位置和仍需人工观察的硬件现象。

### 13.1 分阶段执行与停止条件

#### 阶段 1：访问与兼容性

- 确认私有仓库访问权限；
- 检查 arm64 和 macOS 14+；
- 校验 DMG SHA-256；
- 不满足任一硬条件时停止，不继续绕过安装。

#### 阶段 2：只读环境审计

- 运行本文体检脚本；
- 识别目标平台和探针；
- 输出缺失依赖清单与预计磁盘/下载影响；
- 获得用户同意后才安装大型软件。

#### 阶段 3：软件安装

- 安装 SuperFlash；
- 仅安装对应平台依赖；
- 记录每个工具来源、版本和绝对路径；
- 环境检查未通过时不进入真实烧录。

#### 阶段 4：工程验证

- 只读检查工程结构；
- 先 build；
- 编译失败则处理第一个真实错误；
- 不擅自重构用户固件，不删除用户文件。

#### 阶段 5：硬件验证与烧录

- 确认探针和目标供电；
- 先 verify；
- 获得用户明确允许后才 build-flash；
- 用写入校验、寄存器和硬件现象共同验收。

#### 阶段 6：交付

- 给出成功与失败项；
- 给出报告路径和关键证据；
- 写明用户仍需人工确认的现象；
- 未经许可不 Git、不上传日志、不改变仓库可见性。

## 14. Codex 一键接手提示词

将下面整段复制给新用户的 Codex，并在最后补充实际工程路径、芯片和调试器：

```text
请帮我在这台 Mac 上安装并配置 SuperFlash：
https://github.com/lcqxidian/SuperFlash

该仓库目前可能是 Private。请先确认当前 GitHub 账号已被授权；如果无权访问，请停止并告诉我需要仓库所有者邀请，不要改用来源不明的镜像。

请先完整阅读仓库根目录 README.md、AI接手提示词.md 和 PROJECT_DOCUMENTATION.md，再开始操作。

目标：
1. 检查这台 Mac 是否满足 SuperFlash 条件；
2. 安装 SuperFlash；
3. 根据我的目标芯片和调试器，只安装必要依赖；
4. 配置应用中的工具绝对路径；
5. 先仅编译，再验证调试器连接，最后在我已连接并允许后执行真实烧录；
6. 用 codex_build 下的报告和寄存器/校验输出证明结果，不要只根据界面的“成功”二字判断。

执行约束：
- 先运行只读检查：uname -m、sw_vers、xcode-select、/usr/bin/python3、工具路径和 USB 设备检测；
- 记录仓库提交号和 SuperFlash.dmg 的 SHA-256；
- 如果不是 Apple Silicon arm64 或低于 macOS 14，停止安装当前 DMG 并说明原因；
- 优先使用 GitHub 中的 SuperFlash.dmg；只有 DMG 不适用或需要修复时才从源码构建；
- 所有依赖只从 Apple、Arm、ST、TI、SEGGER、Homebrew 官方来源获取；
- STM32：检查完整 arm-none-eabi 工具链、新标准库、OpenOCD 和 ST-Link；
- TI MSPM0：检查 TI Arm Clang、MSPM0 SDK、DSLite/XDS110，以及需要时的 JLinkExe；
- 老 SAM-ICE 必须保留 DSLite 唤醒 + J-Link 完整 Program & Verify + reset/regs/go 的两阶段流程；
- 不要把开发者的 /Users/lcq 路径复制到我的电脑；
- 修改 /Applications、清除 quarantine、安装大型厂商软件或真实烧录前先告知我；
- 未经我明确许可，不执行任何 Git 写操作，不 add、不 commit、不 push；
- 不要删除或覆盖我的工程文件，不要回退我已有的改动。

完成标准：
- 列出所有已发现和已安装工具的绝对路径与版本；
- SuperFlash 环境检查通过；
- 对我的工程执行 build 成功；
- 连接硬件后执行 verify；
- 经我允许后执行 build-flash；
- 报告最终写入是否经过 verify、CPU 是否无异常运行，以及仍需我人工确认的外设现象。

我的实际信息：
- 工程绝对路径：<填写>
- 芯片完整型号：<例如 STM32F407ZG 或 MSPM0G3507>
- 调试器：<例如 ST-Link V2、XDS110、J-Link、SAM-ICE>
- 我需要：<仅编译 / 编译并烧录 / 调试某个报错>
```

## 15. 维护者资料

- 架构和完整实现说明：[PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md)
- AI 开发接手约束：[AI接手提示词.md](AI接手提示词.md)
- CLI/API：[API文档.md](API文档.md)
- 新建工程说明：[新建项目须知.md](新建项目须知.md)
- 技术路线：[TECHNICAL_ROADMAP.md](TECHNICAL_ROADMAP.md)

如果安装或烧录失败，请保留完整控制台输出和工程 `codex_build/*_REPORT.md`，不要只截取最后一行错误。
