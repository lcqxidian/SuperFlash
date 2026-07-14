# SuperFlash CLI API 文档

## 概述

SuperFlash 支持命令行模式，AI 或自动化脚本可直接通过 CLI 调用编译、烧录、验证功能，无需启动 GUI。

自动检测 STM32 / TI MSPM0 项目类型并选择对应工具链。

## CLI 入口

```bash
/Applications/SuperFlash.app/Contents/MacOS/SuperFlash <命令> <项目路径>
```

## API 命令

| 命令 | 功能 | 执行内容 |
|---|---|---|
| `build` | 仅编译 | 检测项目类型 → 选择工具链 → 编译 → 输出 .elf/.hex/.bin |
| `flash` | 仅烧录 | 检测探头 → 连接芯片 → 烧录 → Reset 运行 |
| `build-flash` | 编译并烧录 | build + flash 串联执行 |
| `verify` | 验证连接 | 检测探头 → 连接芯片 → 读取 PC/SP 寄存器 |

**退出码：** `0` 成功，`1` 失败。

## 使用示例

### 编译 STM32 项目
```bash
/Applications/SuperFlash.app/Contents/MacOS/SuperFlash build "/Users/lcq/Desktop/ORICO/WorkSpace/临时草稿/test8"
```

### 编译并烧录 TI MSPM0 项目
```bash
/Applications/SuperFlash.app/Contents/MacOS/SuperFlash build-flash "/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/Test"
```

### 仅烧录
```bash
/Applications/SuperFlash.app/Contents/MacOS/SuperFlash flash "/Users/lcq/Desktop/ORICO/WorkSpace/电赛代码/Test"
```

## 项目格式支持

### STM32 项目识别条件（满足任一即可）

- 包含 `.ioc` 文件（STM32CubeMX）
- 包含 `startup_stm32*.s` 启动文件
- 包含 `DRIVE/` 或 `Core/` 目录
- 目录名含 `STM32` 字样

**编译器：** ARM GCC (`arm-none-eabi-gcc`)
**烧录器：** OpenOCD + ST-Link 或 STM32CubeProgrammer
**支持系列：** F1, F4, F7, H7, G0, G4, L4

### TI MSPM0 项目识别条件（满足任一即可）

- 包含 `empty.syscfg` 配置文件
- 包含 `targetConfigs/*.ccxml` 调试配置
- 包含 `ti_msp_dl_config.c` 驱动配置

**编译器：** TI Arm Clang (`tiarmclang`)
**烧录器：** DSLite + XDS110 / SAM-ICE / J-Link
**支持芯片：** MSPM0G3507（自动检测，优先 XDS110，失败自动切 J-Link）

## 调用注意事项

1. 项目路径含空格需加引号
2. 项目必须存在且结构完整
3. 首次调用耗时较长（工具链初始化），后续编译更快
4. 构建产物输出到项目 `codex_build/` 目录
5. TI 项目断电后第一次烧录可能较慢（SAM-ICE 初始化 DAP 需多次重试）

## AI 集成示例

```python
import subprocess

def superflash_build(project_path: str) -> bool:
    result = subprocess.run([
        "/Applications/SuperFlash.app/Contents/MacOS/SuperFlash",
        "build-flash",
        project_path,
    ], capture_output=True, text=True)
    return result.returncode == 0
```
