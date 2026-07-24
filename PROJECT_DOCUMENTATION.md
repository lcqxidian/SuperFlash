# SuperFlash — 完整工程文档

## 目录

1. [项目概述](#1-项目概述)
2. [源代码目录结构](#2-源代码目录结构)
3. [STM32 F4 烧录原理（逐行）](#3-stm32-f4-烧录原理)
4. [TI MSPM0 烧录原理（逐行）](#4-ti-mspm0-烧录原理)
5. [Swift 应用层架构](#5-swift-应用层架构)
6. [CLI 命令行接口](#6-cli-命令行接口)
7. [新项目创建向导](#7-新项目创建向导)
8. [已知问题与待办](#8-已知问题与待办)

---

## 1. 项目概述

SuperFlash 是 macOS 原生嵌入式编译烧录工具。SwiftUI 桌面界面，Python 脚本执行实际编译烧录。

- **平台**: macOS 14.0+, ARM64
- **语言**: Swift 6 + Python 3
- **构建**: Swift Package Manager
- **支持芯片**: STM32 (F1/F4/F7/H7/G0/G4/L4) + TI MSPM0G3507

### 工具链依赖

| 角色 | STM32 | TI MSPM0 |
|---|---|---|
| 编译器 | ARM GCC (`arm-none-eabi-gcc`) | TI Arm Clang (`tiarmclang`) |
| 烧录器 | OpenOCD + ST-Link | DSLite + J-Link / XDS110 |
| SDK | 芯片包（CMSIS + HAL/StdPeriph） | MSPM0 SDK |
| 调试协议 | SWD (ST-Link) | SWD (J-Link/SAM-ICE/XDS110) |

---

## 2. 源代码目录结构

```
Sources/SuperFlash/
├── SuperFlashApp.swift           # 入口：GUI 模式或 CLI 模式
├── CLI/
│   └── CLIHandler.swift          # 命令行 API（build/flash/verify）
├── App/
│   └── AppState.swift            # 中心状态机，协调所有操作
├── Models/
│   ├── BuildAction.swift         # build / flash / buildAndFlash / verify
│   ├── DependencyCheck.swift     # 工具链依赖检查结果
│   ├── DiagnosticIssue.swift     # 编译/烧录错误诊断
│   ├── LogEntry.swift            # 日志条目
│   ├── ProjectInfo.swift         # 项目元数据
│   ├── ProjectKind.swift         # keil / makefile / cubeIDE / CCS / bare
│   ├── ProjectVendor.swift       # stm32 / tiMSPM0 / unknown
│   ├── RunState.swift            # idle / building / flashing / success / failed ...
│   ├── STM32Family.swift         # CPU 标志 + OpenOCD 目标配置
│   └── ToolchainInfo.swift       # 检测到的工具路径
├── Services/
│   ├── BuildPlanGenerator.swift  # 选择脚本 + OpenOCD cfg
│   ├── EnvironmentChecker.swift  # 扫描系统找工具链
│   ├── LogParser.swift           # 解析输出判定成功/失败
│   ├── ProjectDetector.swift     # 识别项目类型和芯片型号
│   ├── RecentProjectStore.swift  # 最近项目持久化
│   ├── ReportStore.swift         # 打开构建产物和报告
│   ├── ScriptRunner.swift        # 执行 Python 脚本的进程管理器
│   └── SettingsStore.swift       # 用户设置持久化
├── UI/
│   ├── ContentView.swift         # 主三栏布局
│   ├── DiagnosticView.swift      # 诊断信息显示
│   ├── FloatingBallManager.swift # 悬浮球（进度环 + 快速操作）
│   ├── LogConsoleView.swift      # 编译输出控制台
│   ├── NewProjectView.swift      # 新建 STM32 项目向导
│   ├── ProjectListView.swift     # 最近项目侧边栏
│   ├── ProjectSummaryView.swift  # 项目信息卡片
│   ├── SettingsView.swift        # 设置面板
│   └── StatusBannerView.swift    # 状态横幅
└── Resources/
    ├── scripts/
    │   ├── stm32_build_flash.py   # STM32 构建烧录脚本（1048 行）
    │   └── ti_mspm0_build_flash.py # TI MSPM0 构建烧录脚本（782 行）
    ├── CMSIS/                     # STM32F4 CMSIS 头文件
    ├── CMSIS_F1/                  # STM32F1 CMSIS 头文件
    ├── FWLib/                     # STM32F4 标准外设库
    │   ├── inc/                   # 外设库头文件
    │   ├── src/                   # 外设库源文件
    │   └── stm32f4xx_conf.h       # 外设库配置文件
    └── SuperFlash.icns           # 应用图标
```

---

## 3. STM32 F4 烧录原理

### 3.1 整体流程图

```
用户点击「编译并烧录」
  │
  ▼
AppState.runAction(.buildAndFlash)
  │  1. 检测项目类型 (ProjectDetector)
  │  2. 检查环境 (EnvironmentChecker)
  │  3. 获取脚本路径 (BuildPlanGenerator)
  ▼
ScriptRunner.run(script: "stm32_build_flash.py", project: "...", action: "all")
  │  启动 Python 进程，逐行读取输出
  ▼
stm32_build_flash.py 主流程:
  ├── [1] 查找 ARM GCC 工具链 (find_gcc)
  ├── [2] 检测 MCU 型号 (detect_mcu)
  ├── [3] 收集源文件 (discover_sources)
  ├── [4] 编译所有 .c/.s 文件
  ├── [5] 链接生成 .elf
  └── [6] 烧录 (flash_with_openocd)
```

### 3.2 第一步：查找 ARM GCC（find_gcc）

```python
def find_gcc(override: str | None) -> Path:
    if override and Path(override).is_file():
        return Path(override)
    candidates = [
        Path.home() / "arm-gcc-toolchain/bin/arm-none-eabi-gcc",
        Path("/usr/local/bin/arm-none-eabi-gcc"),
        Path("/opt/homebrew/bin/arm-none-eabi-gcc"),
    ]
    for c in candidates:
        if c.is_file():
            gcc = c
            return gcc
    # 用 which 搜索
    result = shutil.which("arm-none-eabi-gcc")
    if result:
        return Path(result)
    raise SystemExit("arm-none-eabi-gcc not found")
```

先检查用户设置的路径，再搜索常见目录（Homebrew、自定义 toolchain），最后用 shell 的 `which` 查找 PATH。找到后还会编译一个 `#include <stdint.h>` 测试片段验证工具链可用。

如果用户在设置面板指定了 ARM GCC 路径，会通过 `--gcc` 参数传给脚本，跳过自动检测。

### 3.3 第二步：检测 MCU 型号（detect_mcu）

检测优先级从高到低：

```
1. 用户传入 --mcu 参数（最高优先级）
2. 读取 DRIVE/stm32_mcu 文件（新建项目向导写入）
3. 扫描项目文件中的 MCU 型号字符串：
   a. .ioc 文件（CubeMX 生成的配置）
   b. .ld 链接脚本文件名
   c. startup_stm32*.s / startup_stm32*.S 启动文件
   d. Makefile
   e. *.h 头文件内容
   f. 项目目录名（回退）
4. 正则匹配模式：
   - 主模式: STM32[A-Z]\d{3}[A-Z0-9]{0,8}
     例: STM32F407ZG, STM32H743XI
   - 过滤：排除以 "xx" 结尾的假型号（如 STM32F429xx 是库注释）
   - 备用模式: STM32F40_41xxx, STM32F10X_HD 等宏定义
```

找到 MCU 型号后调用 `normalize_mcu()` 转大写、去下划线、去 `_FLASH` 后缀，得到类似 `STM32F407ZG` 的标准形式。

### 3.4 第三步：识别芯片系列（family_from_mcu）

```python
def family_from_mcu(mcu: str) -> str:
    compact = normalize_mcu(mcu)
    if "STM32F0" in compact: return "f0"
    if "STM32F1" in compact: return "f1"
    if "STM32F4" in compact: return "f4"
    if "STM32F7" in compact: return "f7"
    if "STM32H7" in compact: return "h7"
    if "STM32G0" in compact: return "g0"
    if "STM32G4" in compact: return "g4"
    if "STM32L4" in compact: return "l4"
    # 共支持 14 个系列
```

系列决定：
- **编译参数**: `-mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard`
- **预定义宏**: `-DSTM32F40_41xxx`
- **OpenOCD 目标文件**: `target/stm32f4x.cfg`

### 3.5 第四步：收集源文件（discover_sources）

```python
def discover_sources(project, mcu, flash_size_arg, ram_size_arg):
    excluded = {"build", "Debug", "Release", "codex_build", ".git", ...}
    c_sources = []  # .c 文件
    asm_sources = []  # startup_*.s 文件

    # 1. 遍历项目目录（跳过排除目录）
    for path in project.glob("**/*"):
        if path.suffix == ".c":
            c_sources.append(path)
        elif path.suffix in {".s", ".S"}:
            asm_sources.append(path)

    # 2. 排除不兼容文件（如 F407 项目排除 stm32f4xx_fmc.c）
    if "STM32F4" in mcu: incompatible.add("stm32f4xx_fmc.c")

    # 3. 链接脚本：没找到就生成
    if not linker_candidates:
        linker = generate_linker_script(project, mcu, flash_size_arg, ram_size_arg)
    else:
        linker = linker_candidates[0]  # 用项目自带的

    # 4. 启动文件：没找到就生成
    if not startup_candidates:
        startup = generate_startup_file(project, mcu)
        asm_sources.insert(0, startup)  # 最优先
    elif is_armcc_syntax(orig_startup):
        startup = generate_startup_file(project, mcu)  # Keil 语法转 GCC

    # 5. 生成 system_stm32f4xx.c（如果不存在）
    if mcu and no system file found:
        generate empty SystemInit in codex_build/

    return c_sources, asm_sources, linker, startup
```

关键逻辑：
- **排除目录**: `build`, `Debug`, `codex_build`, `.git` 等不参与编译
- **不兼容文件**: F407 没有 FMC，排除 `stm32f4xx_fmc.c`
- **自动生成链接脚本**: 没找到 `.ld` 就根据 MCU 型号推导 Flash/RAM 大小生成
- **自动生成启动文件**: 没找到 `startup_stm32*.s` 就生成，Keil 语法的也会转 GCC
- **自动生成 SystemInit**: 没找到 `system_stm32f4xx.c` 就在 `codex_build/` 生成空实现

### 3.6 生成链接脚本（generate_linker_script）

推导 Flash 和 RAM 大小：

```python
def deduce_flash_size(mcu):
    name = mcu.upper()
    if "G" in name: size = 1024   # STM32F407ZG: 'G' = 1MB
    if "I" in name: size = 2048   # STM32F407ZI: 'I' = 2MB
    ...
    if "H7" in name:
        if "43" in name: return 2048
        if "45" in name: return 2048
        ...
```

用户可在设置面板手动指定 Flash/RAM 大小，优先于自动推导。

生成的链接脚本包含：
- MEMORY 区域定义（FLASH 起始 0x08000000，RAM 起始 0x20000000）
- 标准 section：`.isr_vector`, `.text`, `.rodata`, `.data`, `.bss`
- `_estack`, `_sidata`, `_sdata`, `_edata`, `_sbss`, `_ebss` 链接符号

### 3.7 生成启动文件（generate_startup_file）

生成 GNU AS 语法的汇编启动文件，内容：

```
1. CPU/FPU 指令:
   .cpu cortex-m4
   .fpu fpv4-sp-d16     (F4 系列)
   .thumb

2. 中断向量表（.isr_vector section）:
   .word _estack              # 栈顶（SP 初始值）
   .word Reset_Handler        # 复位向量
   .word NMI_Handler          # 不可屏蔽中断
   .word HardFault_Handler    # 硬件错误
   .word MemManage_Handler    # 内存管理
   .word BusFault_Handler     # 总线错误
   .word UsageFault_Handler   # 用法错误
   .word 0, 0, 0, 0           # 保留
   .word SVC_Handler          # 系统服务调用
   .word DebugMon_Handler     # 调试监控
   .word 0                     # 保留
   .word PendSV_Handler       # 可挂起系统调用
   .word SysTick_Handler      # 系统节拍定时器
   # --- 以下是外部中断（系列专用名称）---
   .word WWDG_IRQHandler
   .word PVD_IRQHandler
   .word TIM5_IRQHandler      # ← 用户可定义 void TIM5_IRQHandler(void)
   ...（F4 约 82 个，F7 约 97 个，F1 约 43 个）
   .word Default_Handler      # 补足 240 个

3. Reset_Handler:
   ldr r1, =_estack    # 设置栈指针
   mov sp, r1
   # 复制 .data 段（Flash → SRAM）
   .L_copy_data: ...
   # 清零 .bss 段
   .L_clear_bss: ...
   # 调用初始化
   bl SystemInit        # 配置时钟
   bl main              # 跳转到用户代码
   b .                  # 死循环（理论上不会到这里）

4. 弱定义外部中断处理函数:
   .weak TIM5_IRQHandler
   .thumb_set TIM5_IRQHandler, Default_Handler
   （用户代码中的 void TIM5_IRQHandler(void) 会覆盖 weak 定义）
```

**关键设计决策：**
- 每个外部中断都在向量表中有独立命名条目（如 `TIM5_IRQHandler`），不是统一的 `Default_Handler`
- 用 `.weak` + `.thumb_set` 把每个中断别名到 `Default_Handler`
- 用户代码中定义的 strong 函数自动覆盖 weak 别名，中断正确路由

### 3.8 编译过程（build_generated）

```python
# 1. 为每个 .c 文件生成编译命令
for src in c_sources:
    cmd = [gcc, "-c",
           "-mcpu=cortex-m4", "-mthumb",
           "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard",
           "-O2", "-g3",
           "-ffunction-sections", "-fdata-sections",
           "-Wall", "-Wno-unused-parameter",
           "-DSTM32F40_41xxx",  # 预定义宏（自动检测）
           "-DUSE_STDPERIPH_DRIVER",  # 如果检测到 StdPeriph
           f"-I{dir1}", f"-I{dir2}", ...,
           "-MMD", "-MP",  # 依赖文件生成
           "-o", obj_path,
           src_path]
    run(cmd)

# 2. 链接
cmd = [gcc,
       f"-T{linker_script}",
       "-Wl,--gc-sections",    # 丢弃未引用的 section
       "-Wl,--print-memory-usage",  # 打印 Flash/RAM 用量
       "-o", elf_path,
       *all_obj_files,
       "-lc", "-lm", "-lnosys"]  # newlib
run(cmd)

# 3. 生成二进制文件
run([objcopy, "-O", "binary", elf, bin])
run([objcopy, "-O", "ihex", elf, hex])
```

编译器输出到 `codex_build/build-gcc/obj/`，保持目录结构：
```
codex_build/build-gcc/obj/
├── codex_build/startup_stm32f407zg_gcc.s.o
├── USER/main.c.o
├── DRIVE/FWLib/src/stm32f4xx_gpio.c.o
├── DRIVE/FWLib/src/stm32f4xx_rcc.c.o
└── DRIVE/CMSIS/system_stm32f4xx.c.o
```

### 3.9 烧录过程（flash_with_openocd）

```python
def flash_with_openocd(project, openocd, elf, target_cfg, args, report):
    # 目标配置文件：target/stm32f4x.cfg（通过 --target-cfg 传入）
    cmd = [
        openocd,
        "-f", "interface/stlink.cfg",   # ST-Link 调试器
        "-f", target_cfg,                # 芯片目标配置
        "-c", "adapter speed 4000",      # SWD 速度 4000kHz
        "-c", f"program {{{elf}}} verify reset exit"
        #     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        #     烧录 → 验证 → 复位芯片 → 退出 OpenOCD
    ]
    code, output = run(cmd, allow_fail=True)

    if code == 0 and ("Verified OK" in output):
        return True  # 成功
    raise SystemExit("OpenOCD flash failed")
```

OpenOCD 命令解析：
- `-f interface/stlink.cfg`: 加载 ST-Link 调试器驱动（HLA/SWD 传输层）
- `-f target/stm32f4x.cfg`: 加载 STM32F4 目标配置（包含 flash 算法）
- `adapter speed 4000`: SWD 时钟 4MHz
- `program {elf} verify reset exit`:
  - `program`: 开始编程
  - `verify`: 烧录后回读校验（逐个 sector 对比）
  - `reset`: 校验通过后硬件复位芯片
  - `exit`: 执行完后 OpenOCD 退出

如果 OpenOCD 不可用，回退到 STM32CubeProgrammer（通过 `--cube` 参数指定路径）。

### 3.10 验证过程（verify_with_openocd）

```python
def verify_with_openocd(project, openocd, target_cfg, args, report):
    cmd = [
        openocd,
        "-f", "interface/stlink.cfg",
        "-f", target_cfg,
        "-c", "adapter speed 4000",
        "-c", "init",               # 初始化调试端口
        "-c", "reset halt",         # 复位并暂停 CPU
        "-c", "reg pc",             # 读取程序计数器（证明代码在运行）
        "-c", "reg sp",             # 读取栈指针（证明芯片响应）
        "-c", "reset run",          # 复位并运行
        "-c", "shutdown"            # 关闭连接
    ]
    code, output = run(cmd, allow_fail=True)
    if code == 0 and "pc (/32)" in output:
        return True
    raise SystemExit("Verify failed")
```

验证逻辑：确认能连上芯片，读取 CPU 寄存器（PC 和 SP），证明芯片正常运行。

---

## 4. TI MSPM0 烧录原理

### 4.1 整体流程图

```
用户点击「编译并烧录」
  │
  ▼
AppState.runAction(.buildAndFlash)
  │  检测为 TI 项目 → 选择 ti_mspm0_build_flash.py
  ▼
ScriptRunner.run(script: "ti_mspm0_build_flash.py", ...)
  ▼
ti_mspm0_build_flash.py 主流程:
  ├── [1] 查找 TI Arm Clang 编译器 (find_cgt_root)
  ├── [2] 查找 MSPM0 SDK (find_sdk_root)
  ├── [3] 检测芯片型号 (detect_device)
  ├── [4] 收集源文件 (parse_ccs_sources / glob fallback)
  ├── [5] 编译所有 .c 文件
  ├── [6] 链接生成 .out (ELF)
  └── [7] 烧录 (choose_probe → DSLite 唤醒/下载 → J-Link 完整写入校验与启动验证)
```

### 4.2 第一步：查找 TI Arm Clang（find_cgt_root）

```python
def find_cgt_root(override):
    if override: return Path(override)
    # 搜索 CCS Theia 安装目录
    for ccstheia in Path("/Applications/ti").glob("ccstheia*"):
        for cgt in (ccstheia / "ccs/tools/compiler").glob("ti-cgt-armllvm_*"):
            return cgt
    # 搜索旧版 CCS
    for ccs in Path("/Applications/ti").glob("ccs*"):
        ...
    raise SystemExit("TI Arm Clang not found")
```

TI Arm Clang 是 `tiarmclang`，基于 LLVM/Clang，由 CCS Theia 安装。脚本在 `/Applications/ti/ccstheia*/ccs/tools/compiler/ti-cgt-armllvm_*/` 中查找。

### 4.3 第二步：查找 MSPM0 SDK（find_sdk_root）

```python
def find_sdk_root(override):
    if override: return Path(override)
    for sdk in Path("/Applications/ti").glob("mspm0_sdk_*"):
        # 验证 SDK 完整性
        startup = sdk / "source/ti/devices/msp/m0p/startup_system_files/ticlang"
        driverlib = sdk / "source/ti/driverlib/lib/ticlang/m0p"
        if startup.exists() and driverlib.exists():
            return sdk
    raise SystemExit("MSPM0 SDK not found")
```

SDK 结构：
```
/Applications/ti/mspm0_sdk_2_04_00_06/
├── source/
│   ├── ti/
│   │   ├── devices/msp/m0p/
│   │   │   └── startup_system_files/ticlang/
│   │   │       └── startup_mspm0g350x_ticlang.c  # 芯片启动文件
│   │   ├── driverlib/lib/ticlang/m0p/             # 驱动库
│   │   └── driverlib/                             # 驱动头文件
│   └── third_party/CMSIS/Core/Include/            # CMSIS 头文件
```

### 4.4 第三步：检测芯片型号（detect_device）

```python
def detect_device(project, override):
    if override: return override

    # 1. 从 ccxml 文件提取
    for ccxml in project.glob("targetConfigs/*.ccxml"):
        text = ccxml.read_text(errors="ignore")
        match = re.search(r"MSPM0[A-Z]\d+", text)
        if match: return match.group(0)

    # 2. 从 ti_msp_dl_config.h 提取
    config_h = project / "ti_msp_dl_config.h"
    if config_h.exists():
        match = re.search(r"MSPM0[A-Z]\d+", config_h.read_text()[:2000])
        if match: return match.group(0)

    # 3. 从 empty.syscfg 提取
    syscfg = project / "empty.syscfg"
    if syscfg.exists():
        match = re.search(r'"MSPM0[A-Z]\d+"', syscfg.read_text()[:5000])
        if match: return match.group(0).strip('"')

    # 4. 目录名回退
    match = re.search(r"MSPM0[A-Z]\d+", str(project))
    if match: return match.group(0)

    raise SystemExit("Cannot detect MSPM0 device")
```

### 4.5 第四步：收集源文件（parse_ccs_sources）

TI CCS 项目的源文件列表写在 `Debug/subdir_vars.mk` 中：

```makefile
# 典型内容：
C_SRCS += ../main.c
C_SRCS += ../Hardware/OLED.c
C_SRCS += ../Hardware/delay.c
S_SRCS += ../Debug/ti_msp_dl_config.c
```

脚本解析这个 Makefile：

```python
def parse_ccs_sources(project):
    mkfile = project / "Debug/subdir_vars.mk"
    if not mkfile.exists():
        return fallback_glob(project)  # 没有 mk 文件就用 glob 扫描

    sources = []
    for line in mkfile.read_text().splitlines():
        if line.strip().startswith("C_SRCS") or line.strip().startswith("S_SRCS"):
            # 提取 += 后的路径
            relpath = line.split("+=")[1].strip()
            if relpath.startswith("../"):
                # CCS 用相对路径，去掉 ../
                relpath = relpath[3:]
            src = project / relpath
            if src.is_file():
                sources.append(src)

    # 额外获取启动文件
    for startup in sdk_root.glob(f"**/startup_mspm0g350x_ticlang.c"):
        sources.append(startup)

    return sources
```

编译命令：

```python
cmd = [
    tiarmclang,
    "-c",
    "-march=thumbv6m",           # ARMv6-M 架构
    "-mcpu=cortex-m0plus",        # Cortex-M0+ 处理器
    "-mfloat-abi=soft",           # 无硬件浮点
    "-mlittle-endian",            # 小端
    "-mthumb",                    # Thumb 指令集
    "-O2", "-gdwarf-3",           # 优化 + 调试信息
    f"-I{project}",
    f"-I{sdk}/source/third_party/CMSIS/Core/Include",
    f"-I{sdk}/source",
    f"-D__MSPM0G3507__",          # 芯片预定义宏
    "-MMD", "-MP",                # 依赖生成
    "-o", obj_path,
    src_path,
]
run(cmd)
```

链接命令：

```python
cmd = [
    tiarmclang,
    "-march=thumbv6m", "-mcpu=cortex-m0plus",
    "-Wl,-m{project}.map",              # 生成 MAP 文件
    "-Wl,-i{sdk}/source",               # SDK 库搜索路径
    "-Wl,-i{compiler}/lib",             # 编译器库搜索路径
    "-Wl,--rom_model",                  # ROM 模式（代码在 Flash 运行）
    "-o", out_path,
    *all_obj_files,
    f"-Wl,-l{device_linker_cmd}",       # 内存布局脚本
    f"-Wl,-l{device_cmd_genlibs}",      # 驱动库链接
    "-Wl,-llibc.a",                      # C 标准库
]
run(cmd)
```

### 4.6 烧录过程（探头选择 + 烧录执行）

TI MSPM0 烧录的独特之处在于有三条烧录路径，按优先级自动选择。

#### 4.6.1 探头检测（choose_probe）

```python
def choose_probe(args):
    """返回探头类型字符串"""
    if args.probe != "auto":
        return args.probe  # 用户手动指定

    dslite = find_dslite(args.dslite)

    # 路径 1：XDS110 在线 → 优先使用
    if dslite and xds110_connected():
        return "xds110"

    # 路径 2：检测到 SAM-ICE / 老 J-Link
    if dslite:
        jlink = find_jlink(args.jlink)
        if jlink:
            probe_info = jlink_probe_description(jlink)
            # SAM-ICE / J-Link ARM-OB STM32：固件旧，DSLite 连接不稳
            if "SAM-ICE" in probe_info or "J-Link ARM-OB" in probe_info:
                return "dslite_jlink"

    # 路径 3：标准 J-Link
    return "jlink"
```

#### 4.6.2 路径 1：XDS110（flash_or_verify_xds110）

XDS110 是 TI LaunchPad 自带的调试器。

```python
def flash_or_verify_xds110(kind, project, info, args, report):
    dslite = find_dslite()
    if not xds110_connected():
        raise SystemExit("XDS110 not detected")

    # 使用生成的 XDS110 ccxml
    ccxml = write_xds110_ccxml(tool_dir, device)

    cmd = [dslite, "flash", f"--config={ccxml}"]
    if kind == "flash":
        cmd.extend(["-e", "-f", "-u", hex_path])
        # -e: 擦除全部 Flash
        # -f: 烧录
        # -u: 运行程序（解除复位）
    else:
        cmd.extend(["-v", hex_path])

    code, output = run(cmd, allow_fail=True)
    if not succeeded:
        # XDS110 失败 → 自动回退到 J-Link
        flash_or_verify_dslite_jlink(kind, project, info, args, report)
```

#### 4.6.3 路径 2：SAM-ICE / J-Link ARM-OB（确定性两阶段烧录）

SAM-ICE 是 Atmel 出品的老 J-Link 变体（2012 年固件）。

```python
def flash_or_verify(kind, project, info, args, report):
    probe = choose_probe(args)
    if probe == "dslite_jlink":
        # 老 SAM-ICE 冷启动时直接使用 JLinkExe 容易 DAP 初始化失败。
        # DSLite 先建立连接并唤醒 DAP；随后 J-Link 重新完整写入并校验固件，
        # 再执行设备级复位、寄存器读取和 go，确认 CPU 已正常启动。
        flash_or_verify_dslite_jlink(kind, project, info, args, report)
```

#### 4.6.4 JLinkExe 直接烧录（flash_or_verify_jlink）

```python
def flash_or_verify_jlink(kind, project, info, args, report):
    jlink = find_jlink(args.jlink)
    script = "jlink_flash.jlink"  # 生成内容如下：
    # flash.jlink 内容:
    #   connect          ← 连接目标
    #   r                ← 复位
    #   h                ← 暂停
    #   loadfile xxx.hex ← 烧录
    #   r                ← 复位
    #   g                ← 运行
    #   exit

    cmd = [jlink, "-NoGui", "1",
           "-Device", device,
           "-If", "SWD",
           "-Speed", "4000",
           "-CommandFile", str(script)]
    code, output = run(cmd, allow_fail=True, silent=True)

    # 解析输出判断成功
    succeeded = code == 0 and jlink_output_succeeded(kind, output)
    return succeeded
```

JLinkExe 的故障检测（`jlink_output_succeeded`）：

```python
def jlink_output_succeeded(kind, output):
    # 先检查失败关键词
    failure_patterns = [
        "Could not connect to the target device",
        "Failed to initialize DAP",
        "Connect failed",
        "Can not attach to CPU",
        "Mass erase failed",
        "Factory reset failed",
        "Error occurred:",
    ]
    if any(p in output for p in failure_patterns):
        return False

    # flash 成功标志
    if kind == "flash":
        return "O.K." in output and "loadfile" in output
    # verify 成功标志
    if kind == "verify":
        return "IPSR = 000" in output and "(NoException)" in output
    return False
```

#### 4.6.5 DSLite + J-Link 两阶段烧录（flash_or_verify_dslite_jlink）

SAM-ICE 和 MSPM0 在冷启动时 DAP 初始化不稳定，因此先让 DSLite 建立连接；不能把 DSLite 的 `Success` 单独作为最终成功，因为实测曾出现较大固件只写入一部分、未写地址仍为 `0xFF` 的假成功。

```python
def flash_or_verify_dslite_jlink(kind, project, info, args, report):
    dslite = find_dslite()

    # 选择 ccxml：优先 J-Link 配置，XDS110 的自动生成 J-Link 版本
    ccxmls = list(project.glob("targetConfigs/*.ccxml"))
    jlink_ccxmls = [c for c in ccxmls
                    if "jlink" in c.read_text().lower()]
    if jlink_ccxmls:
        ccxml = jlink_ccxmls[0]  # 项目自带 J-Link ccxml
    elif ccxmls:
        # 生成 J-Link ccxml（写入 codex_build/）
        ccxml = write_jlink_ccxml(tool_dir, device)
    else:
        raise SystemExit("No ccxml found")

    # 执行 DSLite 烧录
    cmd = [dslite, "flash", f"--config={ccxml}",
           "-e", "-f", "-u", hex_path]
    code, output = run(cmd, allow_fail=True)

    # 成功判定
    succeeded = (code == 0 and
                "success" in output.lower() and
                ("running" in output.lower() or "loaded" in output.lower()))

    # DSLite 成功仅代表连接/下载阶段结束；随后必须让 J-Link 重新完整写入并校验。
    if succeeded:
        succeeded = finalize_mspm0_after_dslite(
            project, info, args, report, program_hex=True
        )
        if succeeded:
            info["flash_verified"] = "jlink_loadfile_verified"
```

`finalize_mspm0_after_dslite()` 生成并执行 J-Link 命令：`connect → halt → device-specific reset → halt → loadfile → reset → halt → regs → go`。成功条件同时要求：

- `loadfile` 输出下载记录及 `O.K.`，证明 J-Link 自带的 Program & Verify 完成；
- 最后一次错误之后读到 `IPSR = 000 (NoException)`；
- `go` 命令确实执行。

`build-flash` 已包含上述完整校验，因此不再重复执行第二轮探针枚举、DSLite 回读和 J-Link 复位；显式 `verify` 命令仍保留独立回读验证。

#### 4.6.6 ccxml 文件

ccxml 是 TI CCS 的调试配置文件，XML 格式。生成两种版本：

**XDS110 版** (用于 TI LaunchPad 自带调试器):
```xml
<configuration id="Texas Instruments XDS110 USB Debug Probe_0">
  <instance href="connections/TIXDS110_Connection.xml" />
  <connection>
    <instance href="drivers/tixds510cs_dap.xml" />
    <instance href="drivers/tixds510cortexM0.xml" />
    <instance href="drivers/tixds510sec_ap.xml" />
  </connection>
</configuration>
```

**J-Link 版** (用于 SAM-ICE / J-Link):
```xml
<configuration id="SEGGER J-Link Emulator_0">
  <instance href="connections/segger_j-link_connection.xml" />
  <connection>
    <instance href="drivers/jlinkcs_dap.xml" />
    <instance href="drivers/jlinkcortexm0p.xml" />
    <instance href="drivers/jlinksec_ap.xml" />
  </connection>
</configuration>
```

关键区别：`drivers/` 下的驱动不同：
- XDS110 用 `tixds510cs_dap.xml` + `tixds510cortexM0.xml`
- J-Link 用 `jlinkcs_dap.xml` + `jlinkcortexm0p.xml`

---

## 5. Swift 应用层架构

### 5.1 入口分流（SuperFlashApp.swift）

```swift
@main
struct SuperFlashApp: App {
    init() {
        let args = CommandLine.arguments
        if args.count >= 2 {
            // CLI 模式：直接执行命令，不启动 GUI
            if let cli = CLIHandler.parse(args) {
                try? cli.run(); exit(0)
            }
        }
        // 否则启动 GUI
    }
}
```

### 5.2 中心状态管理（AppState.swift）

AppState 是 `@MainActor ObservableObject`，所有操作都通过它协调：

```
runAction(.build)
    │
    ├── 1. 检查项目选中 (currentProject)
    ├── 2. 选择构建脚本 (BuildPlanGenerator)
    ├── 3. 构建参数 (--action, --mcu, --flash-size, --ram-size)
    ├── 4. 设置超时（编译 300s，烧录 120s）
    ├── 5. 设置 stdout/termination handler
    │      - stdout → 追加日志 + 更新 runState
    │      - termination → 解析输出判断成功/失败
    └── 6. 项目切换时预热探头（避免烧录时堵塞）
```

### 5.3 CLI 接口（CLIHandler.swift）

```bash
SuperFlash build /path/to/project      # 仅编译
SuperFlash flash /path/to/project      # 仅烧录
SuperFlash build-flash /path/to/project # 编译+烧录
SuperFlash verify /path/to/project     # 验证连接
```

CLI 模式直接调用 Python 脚本，不启动 GUI，退出码 0 成功 1 失败。

### 5.4 项目检测（ProjectDetector.swift）

评分系统：扫描目录特征，给 STM32 和 TI 分别打分，高分者胜出。

| 特征 | STM32 得分 | TI 得分 |
|---|---|---|
| `.ioc` 文件 | +5 | — |
| `.uvprojx` | +4 | — |
| `startup_stm32*.s` | +4 | — |
| `STM32*.ld` | +3 | — |
| `.ccxml` | — | +5 |
| `empty.syscfg` | — | +4 |
| `ti_msp_dl_config.c` | — | +4 |

---

## 6. CLI 命令行接口

```bash
/Applications/SuperFlash.app/Contents/MacOS/SuperFlash <action> <project_path>
```

| 命令 | 说明 |
|---|---|
| `build` | 编译项目（自动识别 STM32/TI） |
| `flash` | 烧录项目 |
| `build-flash` | 编译并烧录 |
| `verify` | 验证芯片连接 |

退出码：`0` 成功，`1` 失败。

---

## 7. 新项目创建向导

新建 STM32 项目时，流程如下：

```
选择芯片系列 → 自动填充型号 → 填写项目名/位置
    │
    ├── 选择外设库：StdPeriph / HAL / LL / 无
    │
    ├── (可选) 下载芯片包到桌面
    │
    └── 创建项目
          ├── USER/main.c           (最小模板)
          ├── DRIVE/CMSIS/          (CMSIS 头文件)
          ├── DRIVE/FWLib/inc/      (外设库头文件，按选择复制)
          ├── DRIVE/FWLib/src/      (外设库源文件)
          └── DRIVE/stm32_mcu       (芯片型号标识)
```

---

## 8. 已知问题与待办

### 高优先级

1. **硬编码路径**: `ScriptRunner.swift` 和 `ti_mspm0_build_flash.py` 中写死 `/Users/lcq/SEGGER_JLink_V950/`，不通用
2. **CMSIS_F7/H7 缺失**: `NewProjectView` 的 `familyMap` 引用了不存在的 `CMSIS_F7` 和 `CMSIS_H7` 目录
3. **CLIHandler 路径解析**: 带空格的项目路径可能被截断
4. **LogParser 成功检测**: 基于子串匹配（如 `"linking"`），可能在错误日志中误判
5. **发布包架构与签名**: 当前 `SuperFlash.dmg` 仅包含 arm64 应用，最低 macOS 14；应用为 ad-hoc 签名且未进行 Developer ID 签名/Apple 公证，Intel Mac 无法直接运行，其他 Mac 首次打开可能被 Gatekeeper 拦截
6. **Python 绝对路径**: `ScriptRunner.swift` 和 `CLIHandler.swift` 固定调用 `/usr/bin/python3`；只有 Homebrew Python、没有 Apple Command Line Tools 的新电脑仍会启动失败
7. **部署脚本资源路径**: `tools/deploy_superflash_app.sh` 仍从 `SuperFlash_SuperFlash.bundle/scripts/` 复制 Python 脚本，但当前 SwiftPM Release 输出位于 `SuperFlash_SuperFlash.bundle/Resources/scripts/`；脚本会在删除旧 App 后中途失败

### 中优先级

8. **SettingsView 下载**: `downloadStdPeriphLib()` 把 300MB ZIP 全读进内存
9. **pkill 误杀**: `ScriptRunner` 的 `pkill -f` 可能结束同一用户的其他 IDE 调试会话
10. **STM32Family 枚举**: 只支持 F1/F4，Python 支持 14 个系列
11. **FloatingBallManager 内存泄漏**: 每次状态更新重建整个 rootView

### 低优先级

12. **进度检测**: 基于输出中的 ` $ ` 字符串，用户代码输出可能干扰
13. **浮动球状态双重同步**: AppState setter 和 ContentView onChange 都更新浮球
14. **报告中的硬编码路径**: Python 脚本引用 `~/.claude/skills/` 路径

---

## 9. 开发记录

### 2026-07-24 - 恢复 TI MSPM0 强制写入校验

Author: Codex

Type: bugfix | test | documentation | release

External changes reviewed:

- `Sources/SuperFlash/Resources/scripts/ti_mspm0_build_flash.py` 曾被改为在 DSLite 前执行一次 JLinkExe 冷启动预连接、DSLite 显式失败后立即重试，并在 J-Link 完整写入/校验失败时仍保留 DSLite 成功结果。隔离模拟证明该版本会错误报告 Flash OK、设置 `jlink_loadfile_verified` 并跳过后续 verify。
- `Sources/SuperFlash/App/AppState.swift` 删除项目目录自动监听。用户明确接受该删除，因此保留；“重新检测”按钮仍可手动刷新项目信息。

Files created:

- `docs/plans/2026-07-24-restore-ti-flash-safety.md`：限定恢复范围、成功判据和验证步骤。

Files modified:

- `Sources/SuperFlash/Resources/scripts/ti_mspm0_build_flash.py`：恢复到已通过 Test5 实机验证的确定性两阶段基线；删除 DSLite 前 JLinkExe 预连接和盲重试，重新要求 J-Link `loadfile`、Program & Verify、设备级复位、寄存器检查和 `go` 全部成功。
- `PROJECT_DOCUMENTATION.md`：记录审查结论、用户接受自动监听删除、恢复验证和部署脚本资源路径问题。

Validation:

- Python AST 语法检查和 `git diff --check` 通过。
- 隔离失败模拟：DSLite 返回 `Running/Success`、J-Link 返回失败时，函数抛出失败、不设置 `flash_verified`、报告不出现 Flash OK。
- 隔离成功模拟：J-Link 返回成功时，函数正常返回并设置 `jlink_loadfile_verified`。
- `swift build -c release` 通过。
- 重新构建并部署 `/Applications/SuperFlash.app`；签名校验通过，可执行文件为 arm64。
- 源码和应用内 `ti_mspm0_build_flash.py` SHA-256 均为 `ef41bf5530b70dcac6f25c924e2ec02f2bd5a1bc7f0df7e651fa924b11348f63`。
- 未执行真实硬件烧录；下一次连接目标板后仍应做一次完全断电再上电的 Test5 `build-flash` 回归。

Known deployment issue:

- `tools/deploy_superflash_app.sh` 使用旧资源路径并在复制脚本时失败。本次按实际 `.build/arm64-apple-macosx/release/SuperFlash_SuperFlash.bundle/Resources/scripts/` 路径手动补齐应用、重建 Info.plist 并重新签名；未在本次范围内修改部署脚本。

Decision:

- DSLite 的 `Success/Running` 不能成为最终成功依据；J-Link 完整写入校验与启动验证失败时必须整体失败。
- 用户允许删除自动监听，因此不恢复 `projectWatcher`。
- 未经用户本人明确允许，不执行任何 Git 写操作；用户已于 2026-07-24 明确授权将当前版本作为“7月24日修复版”提交并推送到 `main`，本次不创建标签或 Release。

### 2026-07-16 - 公开 GitHub 仓库并发布新用户文档

Author: Codex

Type: documentation | release

Files modified:

- `README.md`：将仓库访问说明更新为 Public，提供无需协作者权限的直接克隆方式，并保留来源校验和未来可见性变更约束。
- `PROJECT_DOCUMENTATION.md`：记录仓库公开、安全扫描、用户授权和发布状态，移除已解决的私有仓库访问风险。

Validation:

- 在公开前扫描当前工作区与全部 Git 历史中的常见私钥、GitHub token、AWS key、Slack token 和敏感文件名，未发现命中；`SuperFlash.dmg` 未包含在文本模式扫描中，其应用内容已在此前挂载检查。
- `gh repo view lcqxidian/SuperFlash` 确认仓库由 `PRIVATE` 成功变更为 `PUBLIC`。
- 未登录视角访问 `https://github.com/lcqxidian/SuperFlash` 返回 HTTP 200，确认公开页面可访问。
- `swift build -c release` 通过，验证本地 `3488617` 中的 `AppState.swift` 自动刷新修改可正常构建。
- README 的 26 段 Bash 示例通过 `bash -n`，Markdown 代码围栏配对正确，仓库内相对链接均指向现有文件，`git diff --check` 通过。
- 公开操作使用本机钥匙串中已登录的 GitHub CLI 会话；未使用、验证或保存用户在聊天中提供的明文密码。

Decision:

- 用户明确授权将仓库改为 Public，并上传新用户文档。
- 本地 `main` 上已有用户/外部流程创建的提交 `3488617`，该提交同时包含 README、项目文档和 `AppState.swift` 项目文件自动刷新功能；保持提交原样，不重写历史。
- 验证通过后，将 README Public 状态修订作为独立文档提交推送至 `origin/main`。

### 2026-07-16 - 新用户与 Codex 自动配置指南

Author: Codex

Type: documentation

Files created:

- `README.md`：作为 GitHub 仓库入口，详细说明私有仓库授权、DMG/源码内容、SHA-256 校验、arm64/macOS 14 限制、Gatekeeper 处理、Python 要求、STM32/TI 三种最小依赖方案、只读环境体检、工具自动检测路径、首次验证顺序、硬件安全检查、CLI、成功判据、升级/重置/卸载、问题资料收集，以及可直接交给新用户 Codex 的完整配置提示词。

Files modified:

- `PROJECT_DOCUMENTATION.md`：记录对外分发时的单架构、未公证签名与 `/usr/bin/python3` 绝对路径风险，并登记本次文档工作。

Validation:

- 核对本地 `main` 与 `origin/main` 均为 `1a09a8a`，GitHub 远端为 `https://github.com/lcqxidian/SuperFlash.git`；远端确实包含源码、技术文档、部署脚本与 `SuperFlash.dmg`，此前没有 `README.md`。
- 初次审计时 `gh repo view` 确认仓库为 private，未认证 HTTP 访问返回 404；用户随后明确授权改为 Public，最终状态见上一条发布记录。
- 挂载并只读检查 `SuperFlash.dmg`：包含 `SuperFlash.app`；可执行文件为 arm64，`LSMinimumSystemVersion=14.0`，签名类型为 ad-hoc，无 TeamIdentifier。
- 审查 `EnvironmentChecker.swift`、`SettingsStore.swift`、`ScriptRunner.swift`、`CLIHandler.swift`、部署脚本及两个 Python 烧录脚本，文档中的依赖、搜索路径和配置项与当前代码一致。
- Python 脚本仅导入标准库，不需要 pip 第三方包；应用当前固定调用 `/usr/bin/python3`。
- 未在其他新 Mac 上完成端到端安装验证；不同 macOS、探针与厂商安装器版本仍需按文档执行实机验证。

Decision:

- 使用根目录 `README.md` 作为新用户和 Codex 的统一入口，确保用户只分享 GitHub 链接时也能直接看到安装说明。
- 初次编写时仓库为 private，因此文档加入了访问权限说明；后续按用户明确授权改为 Public。Codex 不得自行改变仓库可见性或邀请成员。
- 依赖按 STM32/TI 与具体探针分支安装，不建议为单一用途一次性安装全部工具。
- 文档编写阶段未执行 Git 写操作；随后本地出现用户/外部流程创建的提交 `3488617`，并由用户明确授权公开和推送。

### 2026-07-14 - 改善 TI MSPM0 冷启动首烧与假成功

Author: Codex

Type: bugfix | test | release

Files modified:

- `Sources/SuperFlash/Resources/scripts/ti_mspm0_build_flash.py`：SAM-ICE 不再先执行已知不可靠的冷启动 JLinkExe 连接；改为 DSLite 唤醒 DAP 后，由 J-Link `loadfile` 完整写入并校验，再执行 MSPM0 设备级 reset/halt/regs/go 确认 CPU 正常运行；`build-flash` 跳过已经由 J-Link 覆盖的重复第二轮验证，显式 `verify` 保持不变。
- `Sources/SuperFlash/App/AppState.swift`：TI MSPM0 不再执行无效的项目切换探针预热。
- `Sources/SuperFlash/Services/ScriptRunner.swift`：禁用 TI `Device UNKNOWN` JLinkExe 预热实现。

Validation:

- `swift build -c release`：通过。
- Python AST 语法检查：通过。
- 烧录后 reset/run 验证逻辑的成功与失败模拟：通过。
- Test4 `--action build`：通过，生成 `.out/.hex/.bin`；项目自身仍有一条 `uint32_t` 搭配 `%lu` 的格式警告。
- 已更新并重新签名 `/Applications/SuperFlash.app`，签名校验通过，应用内 TI 脚本与源码 SHA-256 一致。
- 未执行真实烧录：验证时未连接 SAM-ICE/目标板。必须在目标板完全断电后重新上电，执行一次 `build-flash`，观察首烧耗时、最终 post-flash validation 和 MCU 实际运行状态。
- 后续真实硬件首测：DSLite 完成 Flash 下载，但在 `Setting PC to entry point` 阶段报告 `Trouble Writing Register PC`，同时仍错误输出 `Success`；这验证了此前“显示成功但 MCU 卡死”的假成功来源。JLinkExe 在同一命令中前两次连接失败，后续恢复 DAP 并找到 Cortex-M0。
- 根据硬件首测将后置命令调整为 `connect → halt → device-specific reset → halt → regs → go`，并改为按最后一次错误之后的寄存器读取和 `go` 判断最终状态。手动执行后确认 `Device specific reset executed`，PC 位于固件 `Reset_Handler`（0x352C）。
- 部署新版本后进行不断电 `flash` 回归：约 4.6 秒完成，DSLite 下载无 PC 写入错误，J-Link post-flash reset/validation 为 OK，CLI 退出码 0。仍需目标板完全断电再上电后复测冷启动首烧。
- 目标板彻底断电并重新上电后的首次 `build-flash`：一次成功完成，DSLite 下载正常、J-Link post-flash reset/validation 为 OK、DSLite HEX verification successful、CLI 退出码 0，总耗时 19.25 秒。随后读取 PC=0x34E4 且通用寄存器为正常运行值，证明 MCU 在运行；再次执行设备级复位后 PC 正确位于 `Reset_Handler` 0x352C 并执行 `go`。
- 为保证 `build-flash` 的最终退出状态确定可运行，DSLite `-v` 校验成功后也会再执行一次 J-Link 设备级 reset/register validation/go。最新版已重新构建、部署并签名。
- 最新版再次执行完整 `build-flash` 回归：Flash 后 post-flash validation 为 OK，DSLite HEX verification successful，校验后的第二次 post-flash validation 也为 OK，CLI 退出码 0，总耗时 21.24 秒；任务结束时 MCU 已明确复位并运行。
- Test5（23856 字节）暴露 DSLite 部分写入假成功：DSLite 报告 Success，但 DSLite 与独立 J-Link 均确认地址 0x00000C00 仍为 0xFF，期望值为 0x0D；该地址位于 `main()` 机器代码。根因是老 SAM-ICE 的不稳定 DAP/Flash 下载链，不是项目源码或链接布局。
- 烧录流程升级为确定性两阶段：DSLite 只负责冷启动连接/唤醒 DAP，随后 J-Link 必须执行完整 `loadfile`（自带 Program & Verify）、设备级复位、寄存器验证和 `go`；之后仍执行 DSLite HEX 回读校验及最终 J-Link 复位运行。
- 修复后 Test5 真实 `build-flash` 一次通过：J-Link program/reset/validation OK、DSLite Program verification successful、最终 J-Link reset/validation OK，CLI 退出码 0，总耗时 20.83 秒。由此消除了“小项目可烧、大项目部分写入”的不确定性。
- 对 `--action all` 去除两阶段流程之后重复的第二轮探针枚举、DSLite 回读校验和 J-Link 复位：J-Link `loadfile` 本身已经完成完整 Program & Verify，且同一轮仍执行最终设备级复位、寄存器检查和 `go`；显式 `verify` 操作保持不变。Test5 实机回归一次通过，总耗时由 20.83 秒降到 11.67 秒，减少 9.16 秒（约 44%）。

Decision:

- DSLite 的 `loaded/running` 输出不再单独视为最终成功。只有烧录完成后 JLinkExe 能完成设备级复位并读取到 `IPSR = 000 (NoException)`，才确认烧录后启动成功。
- 未经用户本人明确允许，不执行任何 Git 写操作；本次 Git 提交由用户在 2026-07-14 明确授权，仅包含上述 TI 烧录脚本与项目文档变更，不推送远端。
