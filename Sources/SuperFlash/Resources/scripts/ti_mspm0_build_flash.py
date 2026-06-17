#!/usr/bin/env python3
"""Build, flash, and verify TI MSPM0 CCS projects with TI Arm Clang and J-Link/XDS110."""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def log(message: str) -> None:
    print(f"[ti-build-flash] {message}", flush=True)


def run(cmd: list[str], cwd: Path | None = None, allow_fail: bool = False, silent: bool = False) -> tuple[int, str]:
    printable = " ".join(sh_quote(part) for part in cmd)
    log(f"$ {printable}")
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if proc.stdout and not silent:
        print(proc.stdout, end="" if proc.stdout.endswith("\n") else "\n")
    if proc.returncode and not allow_fail:
        raise SystemExit(f"command failed with exit code {proc.returncode}: {printable}")
    return proc.returncode, proc.stdout or ""


def sh_quote(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./:=@%+-]+", value):
        return value
    return "'" + value.replace("'", "'\\''") + "'"


def version_key(path: Path) -> tuple:
    nums = [int(x) for x in re.findall(r"\d+", path.name)]
    return tuple(nums), path.name


def newest(paths: list[Path]) -> Path | None:
    existing = [p for p in paths if p.exists()]
    if not existing:
        return None
    return sorted(existing, key=version_key)[-1]


def normalize_cgt_root(candidate: Path) -> Path | None:
    candidate = candidate.expanduser()
    if candidate.is_file() and candidate.name == "tiarmclang":
        return candidate.parent.parent
    if candidate.name == "bin" and (candidate / "tiarmclang").exists():
        return candidate.parent
    if (candidate / "bin/tiarmclang").exists():
        return candidate
    return None


def find_cgt_root(override: str | None) -> Path:
    candidates: list[Path] = []
    if override:
        candidates.append(Path(override).expanduser())
    if os.environ.get("CGT_ROOT"):
        candidates.append(Path(os.environ["CGT_ROOT"]).expanduser())
    candidates.extend(Path("/Applications/ti").glob("ccstheia*/ccs/tools/compiler/ti-cgt-armllvm_*"))
    candidates.extend(Path("/Applications/ti").glob("ccs*/ccs/tools/compiler/ti-cgt-armllvm_*"))
    found = [root for p in candidates if (root := normalize_cgt_root(p))]
    root = newest(found)
    if not root:
        raise SystemExit("TI Arm Clang not found. Install CCS/Theia or pass --cgt-root.")
    return root


def find_sdk_root(override: str | None) -> Path:
    candidates: list[Path] = []
    if override:
        candidates.append(Path(override).expanduser())
    if os.environ.get("SDK_ROOT"):
        candidates.append(Path(os.environ["SDK_ROOT"]).expanduser())
    candidates.extend(Path("/Applications/ti").glob("mspm0_sdk_*"))
    found = [p for p in candidates if (p / "source").exists()]
    root = newest(found)
    if not root:
        raise SystemExit("MSPM0 SDK not found. Install the TI MSPM0 SDK or pass --sdk-root.")
    return root


def find_jlink(override: str | None) -> Path:
    candidates: list[Path] = []
    if override:
        candidates.append(Path(override).expanduser())
    if os.environ.get("JLINK"):
        candidates.append(Path(os.environ["JLINK"]).expanduser())
    candidates.extend(
        [
            Path("/Users/lcq/SEGGER_JLink_V950/JLinkExe"),
            Path("/Applications/SEGGER/JLink/JLinkExe"),
            Path("/usr/local/bin/JLinkExe"),
            Path("/opt/homebrew/bin/JLinkExe"),
        ]
    )
    path_value = shutil.which("JLinkExe")
    if path_value:
        candidates.append(Path(path_value))
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return candidate
    raise SystemExit("JLinkExe not found. Install SEGGER J-Link or pass --jlink.")


def find_dslite(override: str | None) -> Path | None:
    candidates: list[Path] = []
    if override:
        candidates.append(Path(override).expanduser())
    if os.environ.get("DSLITE"):
        candidates.append(Path(os.environ["DSLITE"]).expanduser())
    candidates.extend(Path("/Applications/ti").glob("ccstheia*/ccs/ccs_base/DebugServer/bin/DSLite"))
    candidates.extend(Path("/Applications/ti").glob("ccs*/ccs/ccs_base/DebugServer/bin/DSLite"))
    path_value = shutil.which("DSLite")
    if path_value:
        candidates.append(Path(path_value))
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return candidate
    return None


def xds110_connected() -> bool:
    xdsdfu_candidates = list(Path("/Applications/ti").glob("ccstheia*/ccs/ccs_base/common/uscif/xds110/xdsdfu"))
    xdsdfu_candidates.extend(Path("/Applications/ti").glob("ccs*/ccs/ccs_base/common/uscif/xds110/xdsdfu"))
    seen: set[Path] = set()
    for xdsdfu in xdsdfu_candidates:
        if xdsdfu in seen:
            continue
        seen.add(xdsdfu)
        if not xdsdfu.exists():
            continue
        code, output = run([str(xdsdfu), "-e"], allow_fail=True)
        if code == 0 and not re.search(r"Found\s+0\s+devices", output):
            return True
    return False


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def detect_device(project: Path, override: str | None) -> str:
    if override:
        return override.upper()
    search_files: list[Path] = []
    search_files.extend(project.glob("targetConfigs/*.ccxml"))
    search_files.extend(project.glob("Debug/device.opt"))
    search_files.extend(project.glob("**/ti_msp_dl_config.h"))
    search_files.extend(project.glob("*.syscfg"))
    for path in search_files:
        text = read_text(path)
        match = re.search(r"MSPM0[A-Z0-9]+", text, re.IGNORECASE)
        if match:
            return match.group(0).upper()
        match = re.search(r"__MSPM0[A-Z0-9]+__", text, re.IGNORECASE)
        if match:
            return match.group(0).strip("_").upper()
    raise SystemExit("Could not detect MSPM0 device. Pass --device, for example --device MSPM0G3507.")


def find_syscfg_dir(project: Path) -> Path:
    preferred = project / "Debug"
    if (preferred / "ti_msp_dl_config.c").exists():
        return preferred
    matches = list(project.glob("**/ti_msp_dl_config.c"))
    matches = [m for m in matches if "codex_build" not in m.parts]
    if matches:
        return matches[0].parent
    raise SystemExit("ti_msp_dl_config.c not found. Build once in CCS or provide SysConfig outputs.")


def parse_ccs_sources(project: Path) -> list[Path]:
    build_root = project / "Debug"
    sources: list[Path] = []
    for mk in sorted(project.glob("Debug/**/subdir_vars.mk")):
        lines = read_text(mk).splitlines()
        active = False
        for raw in lines:
            stripped = raw.strip()
            if stripped.startswith("C_SRCS"):
                active = True
                tail = stripped.split("+=", 1)[-1].strip()
                if tail and tail != "\\":
                    maybe_add_source(project, build_root, tail, sources)
                continue
            if active:
                if not stripped:
                    active = False
                    continue
                maybe_add_source(project, build_root, stripped, sources)
                if not stripped.endswith("\\"):
                    active = False
    return dedupe_paths(sources)


def maybe_add_source(project: Path, build_root: Path, token: str, sources: list[Path]) -> None:
    value = token.rstrip("\\").strip().strip('"')
    if not value or not value.endswith(".c"):
        return
    if re.match(r"^[A-Za-z]:/", value):
        return
    path = (build_root / value).resolve()
    try:
        path.relative_to(project)
    except ValueError:
        return
    if path.exists() and "codex_build" not in path.parts:
        sources.append(path)


def discover_sources(project: Path, syscfg_dir: Path) -> list[Path]:
    parsed = parse_ccs_sources(project)
    if parsed:
        return parsed
    excluded = {"codex_build", "build", "build-ticlang", ".git", ".metadata"}
    sources: list[Path] = []
    for path in project.glob("**/*.c"):
        rel_parts = path.relative_to(project).parts
        if any(part in excluded for part in rel_parts):
            continue
        if rel_parts[0] == "Debug" and path.name != "ti_msp_dl_config.c":
            continue
        sources.append(path.resolve())
    if (syscfg_dir / "ti_msp_dl_config.c").resolve() not in sources:
        sources.append((syscfg_dir / "ti_msp_dl_config.c").resolve())
    return dedupe_paths(sources)


def dedupe_paths(paths: list[Path]) -> list[Path]:
    seen: set[Path] = set()
    result: list[Path] = []
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            result.append(resolved)
    return result


def startup_source(sdk_root: Path, device: str) -> Path:
    startup_dir = sdk_root / "source/ti/devices/msp/m0p/startup_system_files/ticlang"
    lower = device.lower()
    candidates: list[Path] = []
    if lower[-1:].isdigit():
        candidates.append(startup_dir / f"startup_{lower[:-1]}x_ticlang.c")
    family = re.sub(r"\d$", "x", lower)
    candidates.append(startup_dir / f"startup_{family}_ticlang.c")
    candidates.extend(startup_dir.glob(f"startup_{lower[:8]}*_ticlang.c"))
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise SystemExit(f"Could not find startup file for {device} in {startup_dir}.")


def object_path(build_dir: Path, project: Path, source: Path, suffix: str = "") -> Path:
    try:
        rel = source.resolve().relative_to(project.resolve())
        return build_dir / "obj" / rel.with_suffix(rel.suffix + suffix + ".o")
    except ValueError:
        return build_dir / "obj" / "sdk" / source.with_suffix(source.suffix + suffix + ".o").name


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def make_human_makefile(tool_dir: Path, project: Path, script: Path, args: argparse.Namespace) -> None:
    content = f"""# Generated by ti-build-flash.
# This wrapper keeps project-side build tooling in codex_build/.

PROJECT_DIR := {project}
PYTHON ?= python3

.PHONY: all build flash verify clean

all:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action all

build:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action build

flash:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action flash

verify:
\t$(PYTHON) {script} "$(PROJECT_DIR)" --action verify

clean:
\trm -rf "$(PROJECT_DIR)/codex_build/build-ticlang"
"""
    write_file(tool_dir / "Makefile", content)


def write_jlink_scripts(tool_dir: Path, build_dir: Path, project_name: str) -> tuple[Path, Path]:
    hex_path = build_dir / f"{project_name}.hex"
    flash_script = tool_dir / "jlink_flash.jlink"
    verify_script = tool_dir / "jlink_verify.jlink"
    write_file(
        flash_script,
        f"""connect
r
h
loadfile "{hex_path}"
r
g
exit
""",
    )
    write_file(
        verify_script,
        """connect
Sleep 500
h
regs
g
exit
""",
    )
    return flash_script, verify_script


def write_xds110_ccxml(tool_dir: Path, device: str) -> Path:
    ccxml = tool_dir / "xds110_mspm0.ccxml"
    write_file(
        ccxml,
        f"""<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<configurations XML_version="1.2" id="configurations_0">
    <configuration XML_version="1.2" id="configuration_0">
        <instance XML_version="1.2" desc="Texas Instruments XDS110 USB Debug Probe" href="connections/TIXDS110_Connection.xml" id="Texas Instruments XDS110 USB Debug Probe" xml="TIXDS110_Connection.xml" xmlpath="connections"/>
        <connection XML_version="1.2" desc="Texas Instruments XDS110 USB Debug Probe" id="Texas Instruments XDS110 USB Debug Probe">
            <instance XML_version="1.2" href="drivers/tixds510cs_dap.xml" id="drivers" xml="tixds510cs_dap.xml" xmlpath="drivers"/>
            <instance XML_version="1.2" href="drivers/tixds510cortexM0.xml" id="drivers" xml="tixds510cortexM0.xml" xmlpath="drivers"/>
            <instance XML_version="1.2" href="drivers/tixds510sec_ap.xml" id="drivers" xml="tixds510sec_ap.xml" xmlpath="drivers"/>
            <property Type="choicelist" Value="2" id="SWD Mode Settings">
                <choice Name="SWD Mode - Aux COM port is target TDO pin" value="nothing"/>
            </property>
            <platform XML_version="1.2" id="platform_0">
                <instance XML_version="1.2" desc="{device}" href="devices/{device}.xml" id="{device}" xml="{device}.xml" xmlpath="devices"/>
                <device HW_revision="1" XML_version="1.2" desc="{device}" description="ARM Cortex-M0 Plus MCU" id="{device}" partnum="{device}" simulation="no"/>
            </platform>
        </connection>
    </configuration>
</configurations>
""",
    )
    return ccxml


def jlink_probe_description(jlink: Path) -> str:
    script = Path("/tmp/superflash_jlink_probe_info.jlink")
    write_file(script, "ShowEmuList\nexit\n")
    _, output = run([str(jlink), "-NoGui", "1", "-CommandFile", str(script)], allow_fail=True)
    return output


def jlink_is_restricted_oem(output: str) -> bool:
    # SAM-ICE / J-Link ARM-OB STM32 经测试可用 MSPM0G3507，不拦截
    return False


def build_project(project: Path, args: argparse.Namespace, report: list[str]) -> dict[str, Path | str | list[Path]]:
    cgt_root = find_cgt_root(args.cgt_root)
    sdk_root = find_sdk_root(args.sdk_root)
    device = detect_device(project, args.device)
    syscfg_dir = find_syscfg_dir(project)
    linker_cmd = syscfg_dir / "device_linker.cmd"
    genlibs = syscfg_dir / "device.cmd.genlibs"
    if not linker_cmd.exists():
        matches = list(project.glob("**/*linker*.cmd"))
        if not matches:
            raise SystemExit("device_linker.cmd not found.")
        linker_cmd = matches[0]
    sources = discover_sources(project, syscfg_dir)
    startup = startup_source(sdk_root, device)
    project_name = args.project_name or project.name.replace(" ", "_")
    tool_dir = project / "codex_build"
    build_dir = tool_dir / "build-ticlang"
    out_path = build_dir / f"{project_name}.out"
    hex_path = build_dir / f"{project_name}.hex"
    bin_path = build_dir / f"{project_name}.bin"
    build_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(linker_cmd, build_dir / "device_linker.cmd")
    if genlibs.exists():
        shutil.copy2(genlibs, build_dir / "device.cmd.genlibs")
    else:
        write_file(build_dir / "device.cmd.genlibs", '-l"ti/driverlib/lib/ticlang/m0p/mspm0g1x0x_g3x0x/driverlib.a"\n')

    cc = cgt_root / "bin/tiarmclang"
    objcopy = cgt_root / "bin/tiarmobjcopy"
    size = cgt_root / "bin/tiarmsize"
    common = ["-march=thumbv6m", "-mcpu=cortex-m0plus", "-mfloat-abi=soft", "-mlittle-endian", "-mthumb", "-O2", "-gdwarf-3"]
    include_dirs = [project, syscfg_dir, sdk_root / "source/third_party/CMSIS/Core/Include", sdk_root / "source"]
    include_dirs.extend(sorted({src.parent for src in sources if src.parent != syscfg_dir}))
    includes = [f"-I{p}" for p in include_dirs]
    defines = [f"-D__{device}__"]
    objects: list[Path] = []
    for source in sources + [startup]:
        obj = object_path(build_dir, project, source)
        obj.parent.mkdir(parents=True, exist_ok=True)
        dep = obj.with_suffix(".d")
        cmd = [str(cc), "-c", *common, *includes, *defines, "-MMD", "-MP", f"-MF{dep}", f"-MT{obj}", "-o", str(obj), str(source)]
        run(cmd)
        objects.append(obj)
    link_args = [
        str(cc),
        *common,
        f"-Wl,-m{build_dir / (project_name + '.map')}",
        f"-Wl,-i{sdk_root / 'source'}",
        f"-Wl,-i{cgt_root / 'lib'}",
        "-Wl,--diag_wrap=off",
        "-Wl,--display_error_number",
        "-Wl,--warn_sections",
        f"-Wl,--xml_link_info={build_dir / (project_name + '_linkInfo.xml')}",
        "-Wl,--rom_model",
        "-o",
        str(out_path),
        *[str(o) for o in objects],
        f"-Wl,-l{build_dir / 'device_linker.cmd'}",
        f"-Wl,-l{build_dir / 'device.cmd.genlibs'}",
        "-Wl,-llibc.a",
    ]
    run(link_args)
    _, size_out = run([str(size), str(out_path)], allow_fail=True)
    run([str(objcopy), "-O", "ihex", str(out_path), str(hex_path)])
    run([str(objcopy), "-O", "binary", str(out_path), str(bin_path)])
    make_human_makefile(tool_dir, project, Path(__file__).resolve(), args)
    flash_script, verify_script = write_jlink_scripts(tool_dir, build_dir, project_name)
    report.extend(
        [
            f"Device: {device}",
            f"TI Arm Clang: {cgt_root}",
            f"MSPM0 SDK: {sdk_root}",
            f"SysConfig dir: {syscfg_dir}",
            f"Sources: {len(sources)} project C files + SDK startup",
            "Size output:",
            "```text",
            size_out.strip(),
            "```",
        ]
    )
    return {
        "device": device,
        "cgt_root": cgt_root,
        "sdk_root": sdk_root,
        "tool_dir": tool_dir,
        "build_dir": build_dir,
        "project_name": project_name,
        "hex": hex_path,
        "bin": bin_path,
        "out": out_path,
        "flash_script": flash_script,
        "verify_script": verify_script,
        "xds110_ccxml": write_xds110_ccxml(tool_dir, device),
    }


def choose_probe(args: argparse.Namespace) -> str:
    if args.probe != "auto":
        return args.probe
    dslite = find_dslite(args.dslite)
    if dslite and xds110_connected():
        return "xds110"
    # SAM-ICE / 老 J-Link ARM-OB 的 JLinkExe 冷启动不可靠，直接走 DSLite
    if dslite:
        jlink = find_jlink(args.jlink)
        if jlink:
            probe_info = jlink_probe_description(jlink)
            if "SAM-ICE" in probe_info or "J-Link ARM-OB" in probe_info:
                return "dslite_jlink"
    return "jlink"


def flash_or_verify(kind: str, project: Path, info: dict[str, Path | str | list[Path]], args: argparse.Namespace, report: list[str]) -> None:
    probe = choose_probe(args)
    report.append(f"Selected probe: {probe}")
    if probe == "xds110":
        flash_or_verify_xds110(kind, project, info, args, report)
    elif probe == "dslite_jlink":
        report.append("SAM-ICE detected; using DSLite directly (skipping JLinkExe)")
        log("SAM-ICE detected; using DSLite directly (skipping JLinkExe)")
        if kind == "verify":
            report.append("SAM-ICE/DSLite: verify skipped (device runs immediately after flash)")
            log("SAM-ICE/DSLite: verify skipped (device runs immediately after flash)")
            return
        flash_or_verify_dslite_jlink(kind, project, info, args, report)
    else:
        successfully = flash_or_verify_jlink(kind, project, info, args, report)
        if not successfully:
            report.append("JLinkExe failed; falling back to DSLite + J-Link ccxml")
            dslite = find_dslite(args.dslite)
            if dslite is not None:
                try:
                    flash_or_verify_dslite_jlink(kind, project, info, args, report)
                    log(f"{kind} completed successfully via DSLite+J-Link fallback.")
                except SystemExit:
                    raise SystemExit(f"{kind} failed via both JLinkExe and DSLite/J-Link. See report.")
            else:
                raise SystemExit(f"{kind} failed via JLinkExe and DSLite not found.")


def flash_or_verify_jlink(kind: str, project: Path, info: dict[str, Path | str | list[Path]], args: argparse.Namespace, report: list[str]) -> bool:
    jlink = find_jlink(args.jlink)
    script = info["flash_script"] if kind == "flash" else info["verify_script"]
    cmd = [
        str(jlink),
        "-NoGui",
        "1",
        "-Device",
        str(info["device"]),
        "-If",
        "SWD",
        "-Speed",
        str(args.speed),
        "-CommandFile",
        str(script),
    ]
    code, output = run(cmd, cwd=project, allow_fail=True, silent=True)
    title = "Flash" if kind == "flash" else "Verify"
    succeeded = code == 0 and jlink_output_succeeded(kind, output)
    report.extend([
        f"{title} result via JLinkExe: {'OK' if succeeded else 'FAILED'}",
        f"{title} command exit code: {code}",
        "Note: J-Link Commander can exit with code 0 even when target connection fails; SuperFlash also parses the output.",
        "```text",
        output.strip(),
        "```",
    ])
    return succeeded


def flash_or_verify_dslite_jlink(kind: str, project: Path, info: dict[str, Path | str | list[Path]], args: argparse.Namespace, report: list[str]) -> None:
    """Use DSLite with the project's existing J-Link ccxml as a fallback."""
    if kind == "verify":
        report.append("SAM-ICE/DSLite: verify skipped (device runs immediately after flash)")
        log("SAM-ICE/DSLite: verify skipped (device runs immediately after flash)")
        return
    dslite = find_dslite(args.dslite)
    if dslite is None:
        raise SystemExit("DSLite not found for fallback.")
    ccxmls = list(project.glob("targetConfigs/*.ccxml"))
    if not ccxmls:
        raise SystemExit("No targetConfigs/*.ccxml found for DSLite/J-Link fallback.")
    ccxml = ccxmls[0]
    hex_path = Path(str(info["hex"]))
    title = "Flash" if kind == "flash" else "Verify"
    cmd = [str(dslite), "flash", f"--config={ccxml}", "-e"]
    if kind == "flash":
        cmd.extend(["-f", "-u", str(hex_path)])
    else:
        cmd.extend(["-v", str(hex_path)])
    code, output = run(cmd, cwd=project, allow_fail=True)
    lower = output.lower()
    if kind == "flash":
        succeeded = code == 0 and "success" in lower and ("running" in lower or "loaded" in lower)
    else:
        succeeded = code == 0 and "success" in lower and "verification successful" in lower
        # SAM-ICE 冷启动后第一次 verify 常误报，重试一次即可
        if not succeeded:
            log("Verify failed on first attempt; retrying after warm-up...")
            code, output = run(cmd, cwd=project, allow_fail=True)
            lower = output.lower()
            succeeded = code == 0 and "success" in lower and "verification successful" in lower
    report.extend([
        f"{title} result via DSLite+J-Link: {'OK' if succeeded else 'FAILED'}",
        f"{title} command exit code: {code}",
        "```text",
        output.strip(),
        "```",
    ])
    if not succeeded:
        raise SystemExit(f"{kind} failed via DSLite+J-Link fallback.")


def flash_or_verify_xds110(kind: str, project: Path, info: dict[str, Path | str | list[Path]], args: argparse.Namespace, report: list[str]) -> None:
    dslite = find_dslite(args.dslite)
    if dslite is None:
        raise SystemExit("DSLite not found. Install TI CCS/Theia or pass --dslite.")
    if not xds110_connected():
        raise SystemExit("XDS110 not detected. Connect a TI XDS110 probe or use --probe jlink with a supported generic J-Link.")
    ccxml = Path(str(info["xds110_ccxml"]))
    hex_path = Path(str(info["hex"]))
    title = "Flash" if kind == "flash" else "Verify"
    cmd = [str(dslite), "flash", f"--config={ccxml}", "-e"]
    if kind == "flash":
        cmd.extend(["-f", "-u", str(hex_path)])
    else:
        cmd.extend(["-v", str(hex_path)])
    code, output = run(cmd, cwd=project, allow_fail=True)
    lower = output.lower()
    succeeded = code == 0 and not any(token in lower for token in ["error", "failed", "exception"])
    report.extend([
        f"{title} result: {'OK' if succeeded else 'FAILED'}",
        f"{title} tool: DSLite/XDS110",
        f"{title} command exit code: {code}",
        "```text",
        output.strip(),
        "```",
    ])
    if not succeeded:
        raise SystemExit(f"{title.lower()} failed through DSLite/XDS110. See codex_build/TI_BUILD_FLASH_REPORT.md.")


def jlink_output_succeeded(kind: str, output: str) -> bool:
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
        return "O.K." in output and ("loadfile" in output or "Downloading file" in output or "Flash download" in output)
    if kind == "verify":
        return "IPSR = 000" in output and "(NoException)" in output
    return False


def write_report(project: Path, report: list[str], info: dict[str, Path | str | list[Path]] | None, action: str) -> None:
    tool_dir = project / "codex_build"
    now = _dt.datetime.now().isoformat(timespec="seconds")
    lines = [
        "# TI Build/Flash Report",
        "",
        f"Project: `{project}`",
        f"Action: `{action}`",
        f"Time: `{now}`",
        "",
        "## Results",
        "",
        *[line for item in report for line in (item.splitlines() if "\n" in item else [item])],
        "",
        "## Generated Files",
        "",
        "- `codex_build/Makefile`",
        "- `codex_build/jlink_flash.jlink`",
        "- `codex_build/jlink_verify.jlink`",
        "- `codex_build/xds110_mspm0.ccxml`",
        "- `codex_build/build-ticlang/`",
        "- `codex_build/TI_BUILD_FLASH_REPORT.md`",
        "",
        "## Handoff Prompt",
        "",
        "```text",
        f"请接手这个 TI MSPM0 项目：{project}",
        "所有 Claude/agent 生成的构建/烧录工具都在 codex_build/。",
        "请优先运行：",
        f"python3 ~/.claude/skills/ti-build-flash/scripts/ti_mspm0_build_flash.py \"{project}\" --action all",
        "目标：使用 TI Arm Clang 编译，优先通过 XDS110/DSLite 烧录；没有 XDS110 时才使用受支持的通用 J-Link/SWD。",
        "如果用户还要求 OLED/串口/电机等现象，请先确认当前最小现象稳定，再逐步加回业务逻辑。",
        "```",
        "",
    ]
    write_file(tool_dir / "TI_BUILD_FLASH_REPORT.md", "\n".join(lines))
    log(f"report written: {tool_dir / 'TI_BUILD_FLASH_REPORT.md'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project_dir", nargs="?", default=".", help="TI MSPM0 project directory")
    parser.add_argument("--action", choices=["build", "flash", "verify", "all"], default="all")
    parser.add_argument("--device", help="MSPM0 device name, for example MSPM0G3507")
    parser.add_argument("--project-name", help="output base name")
    parser.add_argument("--sdk-root", help="MSPM0 SDK root")
    parser.add_argument("--cgt-root", help="TI Arm Clang root")
    parser.add_argument("--jlink", help="JLinkExe path")
    parser.add_argument("--dslite", help="TI DSLite path")
    parser.add_argument("--probe", choices=["auto", "xds110", "jlink"], default="auto", help="debug probe backend")
    parser.add_argument("--speed", default="4000", help="J-Link SWD speed in kHz")
    args = parser.parse_args()

    project = Path(args.project_dir).expanduser().resolve()
    if not project.exists():
        raise SystemExit(f"project directory not found: {project}")
    report: list[str] = []
    info: dict[str, Path | str | list[Path]] | None = None
    try:
        if args.action in {"build", "all"}:
            info = build_project(project, args, report)
        else:
            # Rebuild lightweight metadata for flash/verify-only runs.
            device = detect_device(project, args.device)
            project_name = args.project_name or project.name.replace(" ", "_")
            tool_dir = project / "codex_build"
            build_dir = tool_dir / "build-ticlang"
            flash_script, verify_script = write_jlink_scripts(tool_dir, build_dir, project_name)
            info = {
                "device": device,
                "tool_dir": tool_dir,
                "build_dir": build_dir,
                "project_name": project_name,
                "hex": build_dir / f"{project_name}.hex",
                "flash_script": flash_script,
                "verify_script": verify_script,
                "xds110_ccxml": write_xds110_ccxml(tool_dir, device),
            }
        if args.action in {"flash", "all"}:
            if not Path(str(info["hex"])).exists():
                raise SystemExit(f"HEX file not found: {info['hex']}. Run --action build first.")
            flash_or_verify("flash", project, info, args, report)
        if args.action in {"verify", "all"}:
            flash_or_verify("verify", project, info, args, report)
    finally:
        write_report(project, report, info, args.action)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
