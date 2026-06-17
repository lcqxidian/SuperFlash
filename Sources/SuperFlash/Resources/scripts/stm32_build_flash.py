#!/usr/bin/env python3
"""Build, flash, and verify STM32 projects on macOS."""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import re
import shutil
import subprocess
from pathlib import Path


def log(message: str) -> None:
    print(f"[stm32-build-flash] {message}", flush=True)


def sh_quote(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./:=@%+-]+", value):
        return value
    return "'" + value.replace("'", "'\\''") + "'"


def run(cmd: list[str], cwd: Path | None = None, allow_fail: bool = False, env: dict[str, str] | None = None) -> tuple[int, str]:
    printable = " ".join(sh_quote(part) for part in cmd)
    log(f"$ {printable}")
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output = (proc.stdout or b"").decode("utf-8", errors="replace")
    if output:
        print(output, end="" if output.endswith("\n") else "\n")
    if proc.returncode and not allow_fail:
        raise SystemExit(f"command failed with exit code {proc.returncode}: {printable}")
    return proc.returncode, output


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def find_executable(name: str, extra: list[Path] | None = None) -> Path | None:
    candidates = extra[:] if extra else []
    found = shutil.which(name)
    if found:
        candidates.append(Path(found))
    candidates.extend(
        [
            Path.home() / "arm-gcc-toolchain/bin" / name,   # ARM 官方工具链（含完整 newlib）
            Path("/opt/homebrew/bin") / name,
            Path("/usr/local/bin") / name,
        ]
    )
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return candidate
    return None


def find_gcc(override: str | None = None) -> Path:
    """Find a working ARM GCC with newlib support (must compile #include <stdint.h>)."""
    candidates: list[Path] = []
    if override:
        candidates.append(Path(override))
    # Prioritize ARM official toolchain (includes newlib) over Homebrew's (may lack it)
    candidates.append(Path.home() / "arm-gcc-toolchain/bin/arm-none-eabi-gcc")
    path_found = shutil.which("arm-none-eabi-gcc")
    if path_found:
        candidates.append(Path(path_found))
    candidates.extend([
        Path("/opt/homebrew/bin/arm-none-eabi-gcc"),
        Path("/usr/local/bin/arm-none-eabi-gcc"),
    ])
    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        if not candidate.exists() or not os.access(candidate, os.X_OK):
            continue
        # 验证工具链包含 newlib：编译 #include <stdint.h>
        test = subprocess.run(
            [str(candidate), "-c", "-x", "c", "-", "-mcpu=cortex-m4", "-mthumb",
             "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard", "-o", "/dev/null"],
            input="#include <stdint.h>\n", text=True, capture_output=True, timeout=30
        )
        if test.returncode == 0:
            return candidate
        log(f"  (skipping {candidate}: missing newlib/stdint.h)")
    raise SystemExit("No working ARM GCC found. Install ARM GCC with newlib, e.g. from developer.arm.com/downloads/-/arm-gnu-toolchain.")


def find_openocd(override: str | None = None) -> Path | None:
    if override:
        p = Path(override)
        if p.exists() and os.access(p, os.X_OK):
            return p
    return find_executable("openocd")


def find_cube_programmer() -> Path | None:
    candidates = [
        Path("/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI"),
        Path("/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI"),
    ]
    return find_executable("STM32_Programmer_CLI", candidates)


def looks_like_stm32(project: Path) -> bool:
    patterns = ["*.ioc", "**/startup_stm32*.s", "**/startup_stm32*.S", "**/STM32*.ld", "**/stm32*.h"]
    return any(next(project.glob(pattern), None) for pattern in patterns)


def detect_mcu(project: Path, override: str | None) -> str:
    if override:
        return normalize_mcu(override)
    search_files: list[Path] = []
    search_files.extend(project.glob("*.ioc"))
    search_files.extend(project.glob("**/*.ld"))
    search_files.extend(project.glob("**/startup_stm32*.s"))
    search_files.extend(project.glob("**/startup_stm32*.S"))
    search_files.extend(project.glob("**/Makefile"))
    search_files.extend(project.glob("**/*.h"))
    for path in search_files[:300]:
        haystack = path.name + "\n" + read_text(path)[:10000]
        match = re.search(r"STM32[A-Z]\d{3}[A-Z0-9]{0,8}", haystack, re.IGNORECASE)
        if match:
            return normalize_mcu(match.group(0))
        match = re.search(r"STM32F40_41xxx|STM32F4xx|STM32F10X_[A-Z_]+|STM32H7xx|STM32F7xx|STM32G4xx|STM32L4xx", haystack)
        if match:
            return normalize_mcu(match.group(0))
    name_match = re.search(r"STM32[A-Z]\d{3}[A-Z0-9]{0,8}", str(project), re.IGNORECASE)
    if name_match:
        return normalize_mcu(name_match.group(0))
    raise SystemExit("Could not detect STM32 MCU. Pass --mcu, for example --mcu STM32F407ZG.")


def normalize_mcu(value: str) -> str:
    return value.upper().replace("_FLASH", "").replace("_", "")


def family_from_mcu(mcu: str) -> str:
    compact = normalize_mcu(mcu)
    if "STM32F0" in compact:
        return "f0"
    if "STM32F1" in compact:
        return "f1"
    if "STM32F2" in compact:
        return "f2"
    if "STM32F3" in compact:
        return "f3"
    if "STM32F4" in compact or "STM32F4041" in compact:
        return "f4"
    if "STM32F7" in compact:
        return "f7"
    if "STM32H7" in compact:
        return "h7"
    if "STM32G0" in compact:
        return "g0"
    if "STM32G4" in compact:
        return "g4"
    if "STM32L0" in compact:
        return "l0"
    if "STM32L1" in compact:
        return "l1"
    if "STM32L4" in compact:
        return "l4"
    if "STM32U5" in compact:
        return "u5"
    raise SystemExit(f"Unknown STM32 family for MCU {mcu}. Pass --target-cfg.")


def cpu_flags(family: str) -> list[str]:
    table = {
        "f0": ["-mcpu=cortex-m0", "-mthumb"],
        "g0": ["-mcpu=cortex-m0plus", "-mthumb"],
        "l0": ["-mcpu=cortex-m0plus", "-mthumb"],
        "f1": ["-mcpu=cortex-m3", "-mthumb"],
        "l1": ["-mcpu=cortex-m3", "-mthumb"],
        "f2": ["-mcpu=cortex-m3", "-mthumb"],
        "f3": ["-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard"],
        "f4": ["-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard"],
        "g4": ["-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard"],
        "l4": ["-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard"],
        "f7": ["-mcpu=cortex-m7", "-mthumb", "-mfpu=fpv5-sp-d16", "-mfloat-abi=hard"],
        "h7": ["-mcpu=cortex-m7", "-mthumb", "-mfpu=fpv5-d16", "-mfloat-abi=hard"],
        "u5": ["-mcpu=cortex-m33", "-mthumb", "-mfpu=fpv5-sp-d16", "-mfloat-abi=hard"],
    }
    return table[family]


def target_cfg_from_family(family: str, override: str | None) -> str:
    if override:
        return override
    return f"target/stm32{family}x.cfg"


def detect_defines(project: Path, mcu: str, family: str) -> list[str]:
    defines: list[str] = []
    has_hal = bool(list(project.glob("**/*_hal_conf.h"))) or "Core" in [p.name for p in project.iterdir() if p.is_dir()]
    has_stdperiph = bool(list(project.glob("**/stm32*xx_gpio.c"))) and bool(list(project.glob("**/FWLib/**")))
    if has_hal:
        defines.append("USE_HAL_DRIVER")
        exact = exact_hal_define(mcu)
        if exact:
            defines.append(exact)
    if has_stdperiph:
        defines.append("USE_STDPERIPH_DRIVER")
        if family == "f4":
            defines.append("STM32F40_41xxx")
        if family == "f1":
            defines.append("STM32F10X_HD")
    if family == "f4" and "STM32F40_41xxx" not in defines and not has_hal:
        defines.append("STM32F40_41xxx")
    return dedupe(defines)


def exact_hal_define(mcu: str) -> str | None:
    match = re.match(r"(STM32[A-Z]\d{3})([A-Z0-9]{0,3})", normalize_mcu(mcu))
    if not match:
        return None
    prefix = match.group(1)
    suffix = match.group(2)
    if prefix.startswith("STM32F1"):
        return None
    if suffix:
        return prefix + "xx"
    return prefix + "xx"


def dedupe(items: list[str]) -> list[str]:
    seen = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def find_newest_artifact(project: Path, suffixes: tuple[str, ...]) -> Path | None:
    excluded = {".git", "__pycache__"}
    matches = []
    for suffix in suffixes:
        for path in project.glob(f"**/*{suffix}"):
            if any(part in excluded for part in path.parts):
                continue
            matches.append(path)
    if not matches:
        return None
    return max(matches, key=lambda p: p.stat().st_mtime)


def build_with_make(project: Path, gcc: Path, args: argparse.Namespace, report: list[str]) -> Path | None:
    makefile = project / "Makefile"
    if not makefile.exists() or args.force_generated_build:
        return None
    env = os.environ.copy()
    env["PATH"] = str(gcc.parent) + os.pathsep + env.get("PATH", "")
    cmd = ["make"]
    if args.make_target:
        cmd.append(args.make_target)
    cmd.extend([f"TOOLCHAIN={gcc.parent}", f"GNU_INSTALL_ROOT={gcc.parent}/"])
    code, output = run(cmd, cwd=project, allow_fail=True, env=env)
    report.extend(["Build mode: existing Makefile", f"Make exit code: {code}", "```text", tail(output), "```"])
    if code != 0:
        raise SystemExit("make build failed. See codex_build/STM32_BUILD_FLASH_REPORT.md after report is written.")
    artifact = find_newest_artifact(project, (".elf",))
    if not artifact:
        raise SystemExit("Makefile completed but no .elf artifact was found.")
    return artifact


def tail(text: str, max_lines: int = 120) -> str:
    lines = text.splitlines()
    return "\n".join(lines[-max_lines:])


def deduce_flash_size(mcu: str) -> int | None:
    """从 MCU 型号命名推导 Flash 大小（KB），返回字节数或 None。"""
    # 去除常见后缀 G、H、I、U 等封装字母
    mcu = mcu.upper().replace("_FLASH", "")
    # 匹配型号中的容量代码：STM32 + 系列 + 容量代码
    # 如 STM32F407ZG → F4 → 容量代码 ZG → G=1MB
    m = re.search(r"STM32\w+(\d)(\w)$", mcu)
    if not m:
        m = re.search(r"STM32\w+(\w)$", mcu)  # 尝试只取最后一个字母
        size_code = m.group(1) if m else ""
    else:
        # 引脚数后的字母: STM32F407ZG 中的 G
        size_code = m.group(2)

    flash_table = {
        "4": 16, "6": 32, "8": 64, "B": 128,
        "C": 256, "D": 384, "E": 512, "F": 768,
        "G": 1024, "H": 1536, "I": 2048,
        # F1 系列特殊
        "T": 512,
    }
    kb = flash_table.get(size_code)
    if kb:
        return kb * 1024
    return None

def deduce_ram_size(mcu: str, flash_size: int) -> int:
    """根据系列和 Flash 估算 RAM 大小。"""
    mcu_u = mcu.upper()
    # STM32F1: RAM ≈ Flash/3 有上限
    if "STM32F1" in mcu_u:
        return min(flash_size // 3, 0x10000)
    # STM32F4: 典型 128K~192K
    if "STM32F4" in mcu_u:
        if flash_size >= 0x200000:
            return 0x30000  # 192KB
        return 0x20000  # 128KB
    # STM32F0/F3: 较小
    if "STM32F0" in mcu_u or "STM32G0" in mcu_u:
        return min(flash_size // 4, 0x2000)
    # STM32H7: 大 RAM
    if "STM32H7" in mcu_u:
        return max(flash_size // 2, 0x100000)
    # 其他系列按 1/4 估算
    return min(max(flash_size // 4, 0x2000), 0x40000)

def generate_linker_script(project: Path, mcu: str, flash_size_arg: str | None = None, ram_size_arg: str | None = None) -> Path:
    """Generate a linker script for the detected MCU when no .ld is found."""
    # Flash / RAM sizes for common STM32 MCUs (flash_size, ram_size)
    memory_map: dict[str, tuple[int, int]] = {
        "STM32F103C8":  (0x10000,  0x5000),
        "STM32F103CB":  (0x20000,  0x5000),
        "STM32F103RC":  (0x40000,  0xC000),
        "STM32F103VC":  (0x40000,  0xC000),
        "STM32F103ZE":  (0x80000,  0x10000),
        "STM32F407VE":  (0x80000,  0x20000),
        "STM32F407VG":  (0x100000, 0x20000),
        "STM32F407ZE":  (0x80000,  0x20000),
        "STM32F407ZG":  (0x100000, 0x20000),
        "STM32F4ZGT6":  (0x100000, 0x20000),
        "STM32F429ZG":  (0x100000, 0x30000),
        "STM32F429ZI":  (0x200000, 0x30000),
    }
    mcu_key = mcu.upper()
    # 用户手动设置的优先
    if flash_size_arg:
        try: flash_size = int(str(flash_size_arg), 0)
        except: flash_size = 0
    else:
        flash_size = 0
    if ram_size_arg:
        try: ram_size = int(str(ram_size_arg), 0)
        except: ram_size = 0
    else:
        ram_size = 0

    if not flash_size or not ram_size:
        if mcu_key in memory_map:
            fs, rs = memory_map[mcu_key]
            flash_size = flash_size or fs
            ram_size = ram_size or rs
        else:
            deduced = deduce_flash_size(mcu_key)
            if deduced:
                flash_size = flash_size or deduced
                ram_size = ram_size or deduce_ram_size(mcu_key, flash_size)
                log(f"[检测] 从型号名称推导：{mcu_key} → Flash={flash_size//1024}KB RAM={ram_size//1024}KB")
            else:
                flash_size = flash_size or 0x80000
                ram_size = ram_size or 0x20000
                log(f"[检测] 未查到 {mcu_key}，默认 Flash=512KB RAM=128KB，可在设置中手动指定")
    linker_dir = project / "codex_build"
    linker_dir.mkdir(parents=True, exist_ok=True)
    ld_path = linker_dir / "generated_linker.ld"
    flash_origin = "0x08000000"
    ram_origin = "0x20000000"
    content = f"""/* Auto-generated linker script for {mcu} */
ENTRY(Reset_Handler)

MEMORY
{{
    FLASH (rx)  : ORIGIN = {flash_origin}, LENGTH = 0x{flash_size:X}
    RAM   (xrw) : ORIGIN = {ram_origin},    LENGTH = 0x{ram_size:X}
}}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{{
    .isr_vector :
    {{
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    }} > FLASH

    .text :
    {{
        *(.text*)
        *(.rodata*)
        *(.glue_7)
        *(.glue_7t)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
        _etext = .;
    }} > FLASH

    _sidata = .;

    .data : AT(_sidata)
    {{
        _sdata = .;
        *(.data*)
        *(.data.*)
        . = ALIGN(4);
        _edata = .;
    }} > RAM

    .bss :
    {{
        _sbss = .;
        *(.bss*)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    }} > RAM
}}
"""
    ld_path.write_text(content, encoding="utf-8")
    log(f"Generated linker script: {ld_path}")
    return ld_path.resolve()


def generate_startup_file(project: Path, mcu: str) -> Path:
    """Generate a GCC-compatible startup file when the project has Keil/ARMCC syntax startup."""
    startup_dir = project / "codex_build"
    startup_dir.mkdir(parents=True, exist_ok=True)
    startup_path = startup_dir / "startup_stm32f40xx_gcc.s"

    # Standard STM32F40x interrupt vector table in GNU AS syntax
    # 注意：F4 有 Flash alias（0x00000000 映射到 0x08000000）
    # .data 复制必须从 alias 地址读取，否则 D-bus 可能触发总线错误
    content = """\
/* Auto-generated GCC startup file for STM32F4xx */
.syntax unified
.cpu cortex-m4
.fpu fpv4-sp-d16
.thumb

.global g_pfnVectors
.global Default_Handler

/* === 向量表 === */
.section .isr_vector,"a",%progbits
.type g_pfnVectors, %object
g_pfnVectors:
  .word _estack
  .word Reset_Handler
  .word NMI_Handler
  .word HardFault_Handler
  .word MemManage_Handler
  .word BusFault_Handler
  .word UsageFault_Handler
  .word 0
  .word 0
  .word 0
  .word 0
  .word SVC_Handler
  .word DebugMon_Handler
  .word 0
  .word PendSV_Handler
  .word SysTick_Handler
  /* External interrupts */
  .word WWDG_IRQHandler
  .word PVD_IRQHandler
  .word TAMP_STAMP_IRQHandler
  .word RTC_WKUP_IRQHandler
  .word FLASH_IRQHandler
  .word RCC_IRQHandler
  .word EXTI0_IRQHandler
  .word EXTI1_IRQHandler
  .word EXTI2_IRQHandler
  .word EXTI3_IRQHandler
  .word EXTI4_IRQHandler
  .word DMA1_Stream0_IRQHandler
  .word DMA1_Stream1_IRQHandler
  .word DMA1_Stream2_IRQHandler
  .word DMA1_Stream3_IRQHandler
  .word DMA1_Stream4_IRQHandler
  .word DMA1_Stream5_IRQHandler
  .word DMA1_Stream6_IRQHandler
  .word ADC_IRQHandler
  .word CAN1_TX_IRQHandler
  .word CAN1_RX0_IRQHandler
  .word CAN1_RX1_IRQHandler
  .word CAN1_SCE_IRQHandler
  .word EXTI9_5_IRQHandler
  .word TIM1_BRK_TIM9_IRQHandler
  .word TIM1_UP_TIM10_IRQHandler
  .word TIM1_TRG_COM_TIM11_IRQHandler
  .word TIM1_CC_IRQHandler
  .word TIM2_IRQHandler
  .word TIM3_IRQHandler
  .word TIM4_IRQHandler
  .word I2C1_EV_IRQHandler
  .word I2C1_ER_IRQHandler
  .word I2C2_EV_IRQHandler
  .word I2C2_ER_IRQHandler
  .word SPI1_IRQHandler
  .word SPI2_IRQHandler
  .word USART1_IRQHandler
  .word USART2_IRQHandler
  .word USART3_IRQHandler
  .word EXTI15_10_IRQHandler
  .word RTC_Alarm_IRQHandler
  .word OTG_FS_WKUP_IRQHandler
  .word TIM8_BRK_TIM12_IRQHandler
  .word TIM8_UP_TIM13_IRQHandler
  .word TIM8_TRG_COM_TIM14_IRQHandler
  .word TIM8_CC_IRQHandler
  .word DMA1_Stream7_IRQHandler
  .word FSMC_IRQHandler
  .word SDIO_IRQHandler
  .word TIM5_IRQHandler
  .word SPI3_IRQHandler
  .word UART4_IRQHandler
  .word UART5_IRQHandler
  .word TIM6_DAC_IRQHandler
  .word TIM7_IRQHandler
  .word DMA2_Stream0_IRQHandler
  .word DMA2_Stream1_IRQHandler
  .word DMA2_Stream2_IRQHandler
  .word DMA2_Stream3_IRQHandler
  .word DMA2_Stream4_IRQHandler
  .word ETH_IRQHandler
  .word ETH_WKUP_IRQHandler
  .word CAN2_TX_IRQHandler
  .word CAN2_RX0_IRQHandler
  .word CAN2_RX1_IRQHandler
  .word CAN2_SCE_IRQHandler
  .word OTG_FS_IRQHandler
  .word DMA2_Stream5_IRQHandler
  .word DMA2_Stream6_IRQHandler
  .word DMA2_Stream7_IRQHandler
  .word USART6_IRQHandler
  .word I2C3_EV_IRQHandler
  .word I2C3_ER_IRQHandler
  .word OTG_HS_EP1_OUT_IRQHandler
  .word OTG_HS_EP1_IN_IRQHandler
  .word OTG_HS_WKUP_IRQHandler
  .word OTG_HS_IRQHandler
  .word DCMI_IRQHandler
  .word CRYP_IRQHandler
  .word HASH_RNG_IRQHandler
  .word FPU_IRQHandler
.size g_pfnVectors, . - g_pfnVectors

/* === Reset Handler === */
.section .text.Reset_Handler,"ax",%progbits
.type Reset_Handler, %function
.thumb_func
Reset_Handler:
  /* 设置栈指针 */
  ldr r1, =_estack
  mov sp, r1

  /* 配置 Flash 等待周期（F4 @168MHz 需 5WS + PRFTEN + ICEN + DCEN） */
  movw r0, #0x0705
  movw r1, #0x3C00
  movt r1, #0x4002
  str r0, [r1]

  /* .data 复制：从 Flash（alias 地址）复制到 SRAM */
  /* F4 的 Flash alias：0x00000000 映射到 0x08000000 */
  /* 从 D-bus 读 0x0800xxxx 可能触发总线错误，必须从 alias 读 */
  ldr r1, =_sidata
  ldr r2, =_sdata
  ldr r3, =_edata
  subs r3, r2
  ble .L_clear_bss
  /* _sidata 是 0x0800xxxx，减去 0x08000000 得到 alias 地址 0x0000xxxx */
  ldr r0, =0x08000000
  subs r1, r0
.L_copy_data:
  ldrb r0, [r1], #1
  strb r0, [r2], #1
  subs r3, #1
  bne .L_copy_data

  /* 清零 .bss */
.L_clear_bss:
  ldr r1, =_sbss
  ldr r2, =_ebss
  subs r2, r1
  ble .L_call_system_init
  movs r0, #0
.L_zero_bss:
  strb r0, [r1], #1
  subs r2, #1
  bne .L_zero_bss

.L_call_system_init:
  bl SystemInit
  bl main
  b .

/* === 异常处理程序 === */
.macro DEF_IRQ name
.section .text.\\name,"ax",%progbits
.type \\name, %function
.thumb_func
\\name:
  b .
.size \\name, . - \\name
.endm

DEF_IRQ NMI_Handler
DEF_IRQ HardFault_Handler
DEF_IRQ MemManage_Handler
DEF_IRQ BusFault_Handler
DEF_IRQ UsageFault_Handler
DEF_IRQ SVC_Handler
DEF_IRQ DebugMon_Handler
DEF_IRQ PendSV_Handler
DEF_IRQ SysTick_Handler
DEF_IRQ WWDG_IRQHandler
DEF_IRQ PVD_IRQHandler
DEF_IRQ TAMP_STAMP_IRQHandler
DEF_IRQ RTC_WKUP_IRQHandler
DEF_IRQ FLASH_IRQHandler
DEF_IRQ RCC_IRQHandler
DEF_IRQ EXTI0_IRQHandler
DEF_IRQ EXTI1_IRQHandler
DEF_IRQ EXTI2_IRQHandler
DEF_IRQ EXTI3_IRQHandler
DEF_IRQ EXTI4_IRQHandler
DEF_IRQ DMA1_Stream0_IRQHandler
DEF_IRQ DMA1_Stream1_IRQHandler
DEF_IRQ DMA1_Stream2_IRQHandler
DEF_IRQ DMA1_Stream3_IRQHandler
DEF_IRQ DMA1_Stream4_IRQHandler
DEF_IRQ DMA1_Stream5_IRQHandler
DEF_IRQ DMA1_Stream6_IRQHandler
DEF_IRQ ADC_IRQHandler
DEF_IRQ CAN1_TX_IRQHandler
DEF_IRQ CAN1_RX0_IRQHandler
DEF_IRQ CAN1_RX1_IRQHandler
DEF_IRQ CAN1_SCE_IRQHandler
DEF_IRQ EXTI9_5_IRQHandler
DEF_IRQ TIM1_BRK_TIM9_IRQHandler
DEF_IRQ TIM1_UP_TIM10_IRQHandler
DEF_IRQ TIM1_TRG_COM_TIM11_IRQHandler
DEF_IRQ TIM1_CC_IRQHandler
DEF_IRQ TIM2_IRQHandler
DEF_IRQ TIM3_IRQHandler
DEF_IRQ TIM4_IRQHandler
DEF_IRQ I2C1_EV_IRQHandler
DEF_IRQ I2C1_ER_IRQHandler
DEF_IRQ I2C2_EV_IRQHandler
DEF_IRQ I2C2_ER_IRQHandler
DEF_IRQ SPI1_IRQHandler
DEF_IRQ SPI2_IRQHandler
DEF_IRQ USART1_IRQHandler
DEF_IRQ USART2_IRQHandler
DEF_IRQ USART3_IRQHandler
DEF_IRQ EXTI15_10_IRQHandler
DEF_IRQ RTC_Alarm_IRQHandler
DEF_IRQ OTG_FS_WKUP_IRQHandler
DEF_IRQ TIM8_BRK_TIM12_IRQHandler
DEF_IRQ TIM8_UP_TIM13_IRQHandler
DEF_IRQ TIM8_TRG_COM_TIM14_IRQHandler
DEF_IRQ TIM8_CC_IRQHandler
DEF_IRQ DMA1_Stream7_IRQHandler
DEF_IRQ FSMC_IRQHandler
DEF_IRQ SDIO_IRQHandler
DEF_IRQ TIM5_IRQHandler
DEF_IRQ SPI3_IRQHandler
DEF_IRQ UART4_IRQHandler
DEF_IRQ UART5_IRQHandler
DEF_IRQ TIM6_DAC_IRQHandler
DEF_IRQ TIM7_IRQHandler
DEF_IRQ DMA2_Stream0_IRQHandler
DEF_IRQ DMA2_Stream1_IRQHandler
DEF_IRQ DMA2_Stream2_IRQHandler
DEF_IRQ DMA2_Stream3_IRQHandler
DEF_IRQ DMA2_Stream4_IRQHandler
DEF_IRQ ETH_IRQHandler
DEF_IRQ ETH_WKUP_IRQHandler
DEF_IRQ CAN2_TX_IRQHandler
DEF_IRQ CAN2_RX0_IRQHandler
DEF_IRQ CAN2_RX1_IRQHandler
DEF_IRQ CAN2_SCE_IRQHandler
DEF_IRQ OTG_FS_IRQHandler
DEF_IRQ DMA2_Stream5_IRQHandler
DEF_IRQ DMA2_Stream6_IRQHandler
DEF_IRQ DMA2_Stream7_IRQHandler
DEF_IRQ USART6_IRQHandler
DEF_IRQ I2C3_EV_IRQHandler
DEF_IRQ I2C3_ER_IRQHandler
DEF_IRQ OTG_HS_EP1_OUT_IRQHandler
DEF_IRQ OTG_HS_EP1_IN_IRQHandler
DEF_IRQ OTG_HS_WKUP_IRQHandler
DEF_IRQ OTG_HS_IRQHandler
DEF_IRQ DCMI_IRQHandler
DEF_IRQ CRYP_IRQHandler
DEF_IRQ HASH_RNG_IRQHandler
DEF_IRQ FPU_IRQHandler
"""
    startup_path.write_text(content, encoding="utf-8")
    log(f"Generated GCC startup file: {startup_path}")
    return startup_path.resolve()


def is_armcc_syntax(startup: Path) -> bool:
    """Check if a startup file uses ARMCC/Keil syntax (AREA/DCD/PROC)."""
    text = read_text(startup)[:8000].upper()
    return "AREA" in text or ("DCD" in text and "PROC" in text)


def discover_sources(project: Path, mcu: str | None = None, flash_size_arg: str | None = None, ram_size_arg: str | None = None) -> tuple[list[Path], list[Path], Path, Path]:
    excluded = {"build", "Debug", "Release", "codex_build", ".git", ".settings", "cmake-build-debug", "cmake-build-release"}
    # ST 标准外设库中与当前芯片不兼容的文件（如 FMC 在 F407 上为 FSMC）
    incompatible: set[str] = set()
    if mcu and ("STM32F4" in mcu.upper() or "STM32F40" in mcu.upper()):
        incompatible.add("stm32f4xx_fmc.c")
    c_sources: list[Path] = []
    asm_sources: list[Path] = []
    for path in project.glob("**/*"):
        if not path.is_file():
            continue
        rel = path.relative_to(project)
        if any(part in excluded for part in rel.parts):
            continue
        if path.name.startswith("._"):
            continue
        if path.suffix == ".c":
            if path.name in incompatible:
                continue
            c_sources.append(path.resolve())
        elif path.suffix in {".s", ".S"} and "startup_stm32" in path.name.lower():
            asm_sources.append(path.resolve())
    linker_candidates = [p for p in project.glob("**/*.ld") if "codex_build" not in p.parts]
    if not linker_candidates:
        if mcu:
            log(f"No .ld found; generating linker script for {mcu}")
            linker = generate_linker_script(project, mcu, flash_size_arg, ram_size_arg)
        else:
            raise SystemExit("No linker script (.ld) found. Pass --mcu to auto-generate one.")
    else:
        linker = sorted(linker_candidates, key=lambda p: (len(p.parts), p.name))[0].resolve()
    startup_candidates = [p for p in asm_sources if "startup_stm32" in p.name.lower()]
    if not startup_candidates:
        raise SystemExit("No startup_stm32*.s file found.")
    orig_startup = sorted(startup_candidates, key=lambda p: (len(p.parts), p.name))[0].resolve()
    if is_armcc_syntax(orig_startup) and mcu:
        log(f"Startup file {orig_startup.name} uses ARMCC syntax; generating GCC-compatible version")
        startup = generate_startup_file(project, mcu)
    else:
        startup = orig_startup
    # 如果用生成的 GCC 启动文件替换了 Keil/ARMCC 文件，把原文件从源列表中移除
    asm_sources = [startup] + [p for p in asm_sources if p != orig_startup]
    return c_sources, asm_sources, linker, startup


def include_dirs(project: Path, sources: list[Path]) -> list[Path]:
    dirs = {project}
    for src in sources:
        dirs.add(src.parent)
    for header in project.glob("**/*.h"):
        if "codex_build" not in header.parts and ".git" not in header.parts:
            dirs.add(header.parent.resolve())
    return sorted(dirs)


def object_path(build_dir: Path, project: Path, source: Path) -> Path:
    try:
        rel = source.resolve().relative_to(project.resolve())
    except ValueError:
        rel = Path(source.name)
    return build_dir / "obj" / rel.with_suffix(rel.suffix + ".o")


def build_generated(project: Path, gcc: Path, mcu: str, family: str, args: argparse.Namespace, report: list[str]) -> Path:
    c_sources, asm_sources, linker, startup = discover_sources(project, mcu, args.flash_size, args.ram_size)
    build_dir = project / "codex_build/build-gcc"
    project_name = args.project_name or project.name.replace(" ", "_")
    elf = build_dir / f"{project_name}.elf"
    bin_path = build_dir / f"{project_name}.bin"
    hex_path = build_dir / f"{project_name}.hex"
    objcopy = gcc.parent / "arm-none-eabi-objcopy"
    size = gcc.parent / "arm-none-eabi-size"
    flags = cpu_flags(family)
    defs = detect_defines(project, mcu, family)
    incs = include_dirs(project, c_sources + asm_sources)
    incs.append(project / "codex_build")  # 确保 codex_build/ 中的生成文件（stdint.h 等）可被找到
    # ARM GCC 16.1.0 from Homebrew 缺少 newlib stdint.h，#include_next 链会断
    # 生成一个最小 stdint.h 到 codex_build/，用 -I 优先找到它来避免触发 include_next
    stdint_h = project / "codex_build/stdint.h"
    if not stdint_h.exists():
        stdint_h.write_text("""/* Auto-generated stdint.h for ARM GCC without newlib */
#ifndef _STDINT_H
#define _STDINT_H
typedef signed char int8_t;
typedef short int int16_t;
typedef int int32_t;
typedef long long int64_t;
typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
#define INT8_MIN (-128)
#define INT16_MIN (-32768)
#define INT32_MIN (-2147483648)
#define INT64_MIN (-9223372036854775808LL)
#define INT8_MAX 127
#define INT16_MAX 32767
#define INT32_MAX 2147483647
#define INT64_MAX 9223372036854775807LL
#define UINT8_MAX 255
#define UINT16_MAX 65535
#define UINT32_MAX 4294967295U
#define UINT64_MAX 18446744073709551615ULL
#endif
""", encoding="utf-8")
    common = [
        *flags,
        "-O2",
        "-g3",
        "-ffunction-sections",
        "-fdata-sections",
        "-Wall",
        "-Wno-unused-parameter",
        *[f"-D{d}" for d in defs],
        *[f"-I{d}" for d in incs],
    ]
    objects: list[Path] = []
    for source in asm_sources + c_sources:
        obj = object_path(build_dir, project, source)
        obj.parent.mkdir(parents=True, exist_ok=True)
        run([str(gcc), "-c", *common, "-MMD", "-MP", "-o", str(obj), str(source)])
        objects.append(obj)
    link_cmd = [
        str(gcc),
        *flags,
        f"-T{linker}",
        "-Wl,--gc-sections",
        "-Wl,--print-memory-usage",
        "-o",
        str(elf),
        *[str(o) for o in objects],
        "-lc",
        "-lm",
        "-lnosys",
    ]
    run(link_cmd)
    _, size_output = run([str(size), str(elf)], allow_fail=True)
    if objcopy.exists():
        run([str(objcopy), "-O", "binary", str(elf), str(bin_path)])
        run([str(objcopy), "-O", "ihex", str(elf), str(hex_path)])
    write_generated_makefile(project, mcu, family)
    report.extend(
        [
            "Build mode: generated GCC build",
            f"Linker: {linker}",
            f"Startup: {startup}",
            f"Sources: {len(c_sources)} C + {len(asm_sources)} assembly",
            f"Defines: {' '.join(defs) if defs else '(none)'}",
            "Size output:",
            "```text",
            size_output.strip(),
            "```",
        ]
    )
    return elf


def write_generated_makefile(project: Path, mcu: str, family: str) -> None:
    script = Path(__file__).resolve()
    content = f"""# Generated by stm32-build-flash.
PROJECT_DIR := {project}
PYTHON ?= python3

.PHONY: all build flash verify clean

all:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action all --mcu {mcu}

build:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action build --mcu {mcu}

flash:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action flash --mcu {mcu}

verify:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action verify --mcu {mcu}

clean:
\trm -rf "$(PROJECT_DIR)/codex_build/build-gcc"
"""
    write_file(project / "codex_build/Makefile.stm32", content)


def openocd_success(kind: str, output: str) -> bool:
    # 明确成功信号优先于失败关键字检测，避免 "Unable to match requested speed" 等无警告误判
    if "Verified OK" in output or "** Verified OK **" in output:
        return True
    failure_patterns = [
        "Error:",
        "error:",
        "failed",
        "Failed",
        "No device",
        "no device",
        "timed out",
        "Target not examined",
        "verification failed",
    ]
    if any(pattern in output for pattern in failure_patterns):
        return False
    if kind == "flash":
        return "verified" in output.lower() or "verified" in output
    if kind == "verify":
        lower = output.lower()
        return "target halted" in lower or "halted due to" in lower or "info : halted" in lower
    return False


def flash_with_openocd(project: Path, openocd: Path, elf: Path, target_cfg: str, args: argparse.Namespace, report: list[str]) -> None:
    cmd = [
        str(openocd),
        "-f", args.interface_cfg,
        "-f", target_cfg,
        "-c", f"adapter speed {args.adapter_speed}",
        "-c", f"program {{{elf}}} verify reset exit",
    ]
    code, output = run(cmd, cwd=project, allow_fail=True)
    report.extend(["Flash tool: OpenOCD", f"OpenOCD flash exit code: {code}", "```text", output.strip(), "```"])
    if code != 0 or not openocd_success("flash", output):
        raise SystemExit("OpenOCD flash failed. See codex_build/STM32_BUILD_FLASH_REPORT.md.")


def verify_with_openocd(project: Path, openocd: Path, target_cfg: str, args: argparse.Namespace, report: list[str]) -> None:
    cmd = [
        str(openocd),
        "-f",
        args.interface_cfg,
        "-f",
        target_cfg,
        "-c",
        f"adapter speed {args.adapter_speed}",
        "-c",
        "init",
        "-c",
        "reset halt",
        "-c",
        "reg pc",
        "-c",
        "reg sp",
        "-c",
        "reset run",
        "-c",
        "shutdown",
    ]
    code, output = run(cmd, cwd=project, allow_fail=True)
    report.extend(["Verify tool: OpenOCD", f"OpenOCD verify exit code: {code}", "```text", output.strip(), "```"])
    if code != 0 or not openocd_success("verify", output):
        raise SystemExit("OpenOCD verify failed. See codex_build/STM32_BUILD_FLASH_REPORT.md.")


def cube_flash(project: Path, cube: Path, elf: Path, report: list[str]) -> None:
    cmd = [str(cube), "-c", "port=SWD", "-w", str(elf), "-v", "-rst"]
    code, output = run(cmd, cwd=project, allow_fail=True)
    report.extend(["Flash tool: STM32CubeProgrammer", f"CubeProgrammer exit code: {code}", "```text", output.strip(), "```"])
    if code != 0 or "Error" in output or "failed" in output.lower():
        raise SystemExit("STM32CubeProgrammer flash failed. See codex_build/STM32_BUILD_FLASH_REPORT.md.")


def write_report(project: Path, action: str, report: list[str], artifact: Path | None, mcu: str | None, family: str | None, target_cfg: str | None) -> None:
    now = _dt.datetime.now().isoformat(timespec="seconds")
    lines = [
        "# STM32 Build/Flash Report",
        "",
        f"Project: `{project}`",
        f"Action: `{action}`",
        f"Time: `{now}`",
        f"MCU: `{mcu or 'unknown'}`",
        f"Family: `{family or 'unknown'}`",
        f"OpenOCD target: `{target_cfg or 'unknown'}`",
        f"Artifact: `{artifact or 'none'}`",
        "",
        "## Results",
        "",
        *report,
        "",
        "## Handoff Prompt",
        "",
        "```text",
        f"请接手这个 STM32 项目：{project}",
        "所有 agent 生成的构建/烧录工具和报告都在 codex_build/。",
        "请优先运行：",
        f"python3 ~/.claude/skills/stm32-build-flash/scripts/stm32_build_flash.py \"{project}\" --action all",
        "目标：使用 ARM GCC 编译，通过 OpenOCD/ST-Link 烧录，并验证烧录结果。",
        "如果已有 Makefile，请优先复用；如果没有 Makefile，脚本会在 codex_build/build-gcc/ 下生成临时构建。",
        "```",
        "",
    ]
    write_file(project / "codex_build/STM32_BUILD_FLASH_REPORT.md", "\n".join(lines))
    log(f"report written: {project / 'codex_build/STM32_BUILD_FLASH_REPORT.md'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project_dir", nargs="?", default=".", help="STM32 project directory")
    parser.add_argument("--action", choices=["build", "flash", "verify", "all"], default="all")
    parser.add_argument("--mcu", help="STM32 MCU name, for example STM32F407ZG")
    parser.add_argument("--target-cfg", help="OpenOCD target config, for example target/stm32f4x.cfg")
    parser.add_argument("--interface-cfg", default="interface/stlink.cfg", help="OpenOCD interface config")
    parser.add_argument("--adapter-speed", default="4000", help="OpenOCD adapter speed in kHz")
    parser.add_argument("--project-name", help="output base name for generated builds")
    parser.add_argument("--make-target", help="target to pass to existing Makefile")
    parser.add_argument("--force-generated-build", action="store_true", help="ignore existing Makefile and generate GCC build")
    parser.add_argument("--flash-size", default="", help="Flash size override, e.g. 0x100000")
    parser.add_argument("--ram-size", default="", help="RAM size override, e.g. 0x20000")
    parser.add_argument("--gcc", help="path to arm-none-eabi-gcc")
    parser.add_argument("--openocd", help="path to openocd")
    args = parser.parse_args()

    project = Path(args.project_dir).expanduser().resolve()
    if not project.exists():
        raise SystemExit(f"project directory not found: {project}")
    if not looks_like_stm32(project):
        log("warning: project does not obviously look like STM32; continuing because user explicitly invoked the tool")

    report: list[str] = []
    artifact: Path | None = None
    mcu: str | None = None
    family: str | None = None
    target_cfg: str | None = None
    try:
        gcc = find_gcc(args.gcc)
        mcu = detect_mcu(project, args.mcu)
        family = family_from_mcu(mcu)
        target_cfg = target_cfg_from_family(family, args.target_cfg)
        report.extend([f"ARM GCC: {gcc}", f"Detected MCU: {mcu}", f"Detected family: {family}", f"OpenOCD target config: {target_cfg}"])

        if args.action in {"build", "all"}:
            artifact = build_with_make(project, gcc, args, report)
            if artifact is None:
                artifact = build_generated(project, gcc, mcu, family, args, report)
        elif args.action == "flash":
            artifact = find_newest_artifact(project, (".elf",))
            if not artifact:
                raise SystemExit("No .elf artifact found. Run --action build first.")
        # verify action does not require artifact

        if args.action in {"flash", "all"}:
            openocd = find_openocd(args.openocd)
            if openocd:
                flash_with_openocd(project, openocd, artifact, target_cfg, args, report)
            else:
                cube = find_cube_programmer()
                if not cube:
                    raise SystemExit("Neither openocd nor STM32_Programmer_CLI found.")
                cube_flash(project, cube, artifact, report)

        if args.action in {"verify", "all"}:
            openocd = find_openocd(args.openocd)
            if not openocd:
                report.append("Verify skipped: OpenOCD not found.")
            else:
                verify_with_openocd(project, openocd, target_cfg, args, report)
    finally:
        write_report(project, args.action, report, artifact, mcu, family, target_cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
