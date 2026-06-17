import Foundation

struct LogParser {

    func parseDiagnostics(log: String, vendor: ProjectVendor, succeeded: Bool = false) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        let lower = log.lowercased()

        if lower.contains("arm-none-eabi-gcc: command not found") || lower.contains("arm-none-eabi-gcc: not found") {
            issues.append(DiagnosticIssue(
                title: "未找到 ARM GCC",
                detail: "在 PATH 或常用目录中未找到 arm-none-eabi-gcc。",
                suggestion: "通过 Homebrew 安装 ARM GCC：brew install arm-none-eabi-gcc"
            ))
        }

        if lower.contains("openocd: command not found") {
            issues.append(DiagnosticIssue(
                title: "未找到 OpenOCD",
                detail: "在 PATH 或常用目录中未找到 OpenOCD。",
                suggestion: "通过 Homebrew 安装 OpenOCD：brew install openocd"
            ))
        }

        if lower.contains("unsupported j-link probe") || lower.contains("productname: sam-ice") || lower.contains("restricted/oem j-link") {
            issues.append(DiagnosticIssue(
                title: "当前 J-Link 不支持 TI MSPM0",
                detail: "检测到 SAM-ICE 或受限 OEM J-Link。SEGGER 官方限制这类探针只能用于对应厂商芯片，不能可靠烧录 TI MSPM0。",
                suggestion: "请改用 TI XDS110（推荐，SuperFlash 会自动走 DSLite），或使用真正的通用 SEGGER J-Link BASE/PLUS/EDU。"
            ))
        }

        if lower.contains("failed to initialize dap") {
            issues.append(DiagnosticIssue(
                title: "J-Link DAP 初始化失败",
                detail: "J-Link 检测到目标电压，但无法通过 SWD 进入 MSPM0 调试端口。",
                suggestion: "重点检查 MSPM0 的 PA20/SWCLK、PA19/SWDIO、GND、VTref 和 NRST。若使用 LP-MSPM0G3507，请确认 J101 15:16 和 J101 13:14 调试跳线处于连接状态；如果外接 J-Link，请确认 SWDIO/SWCLK 没接反且与板载 XDS110 不冲突。"
            ))
        }

        if lower.contains("could not connect to the target device") {
            issues.append(DiagnosticIssue(
                title: "无法连接到目标",
                detail: "调试探针无法连接到目标设备。",
                suggestion: "先断开其他 CCS/J-Link 会话，再降低 SWD 速度重试。若仍失败，请按 PA20=SWCLK、PA19=SWDIO、GND、VTref、NRST 逐根确认。"
            ))
        }

        if lower.contains("target not examined") || lower.contains("no device") {
            issues.append(DiagnosticIssue(
                title: "未检测到 ST-Link/目标",
                detail: "OpenOCD 无法检测到 ST-Link 或目标设备。",
                suggestion: "1. 检查 ST-Link USB 连接\n2. 确认目标板供电\n3. 检查 SWD 接线\n4. 结束其他 OpenOCD 进程"
            ))
        }

        if lower.contains("verification failed") || lower.contains("verify failed") {
            issues.append(DiagnosticIssue(
                title: "烧录验证失败",
                detail: "烧录的内容与预期的二进制文件不匹配。",
                suggestion: "尝试重新烧录。如果仍然失败，请检查目标时钟和烧录时序设置。"
            ))
        }

        if lower.contains("no such file") || lower.contains("not found") {
            issues.append(DiagnosticIssue(
                title: "文件未找到",
                detail: "未找到所需文件（源文件、链接脚本或二进制文件）。",
                suggestion: "请检查所有源文件是否存在以及项目中的路径是否正确。"
            ))
        }

        if lower.contains("command not found") || lower.contains("not a valid command") {
            issues.append(DiagnosticIssue(
                title: "缺少工具",
                detail: "所需的编译/烧录工具缺失或不在 PATH 中。",
                suggestion: "请确保所有必需的工具链已安装并位于 PATH 中。"
            ))
        }

        if issues.isEmpty && vendor != .unknown && !succeeded {
            let exitKeywords = ["error:", "failed", "can't", "cannot", "unable to", "timed out"]
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
            "error occurred", "failed to initialize dap", "could not connect",
            "target not examined", "no device", "verification failed",
            "command not found", "target connection not established",
            "can not attach to cpu"
        ]
        let hasFailure = failureKeywords.contains { lower.contains($0) }
        if hasFailure { return false }

        switch action {
        case .build:
            return buildSucceeded(lower)
        case .flash:
            return lower.contains("verified") || lower.contains("verification successful") || lower.contains("o.k.")
        case .verify:
            return lower.contains("ipsr = 000") || lower.contains("target halted") || lower.contains("o.k.")
        case .buildAndFlash:
            // DSLite flash with SAM-ICE skips verify (device runs immediately),
            // so also accept "Success" from the flash step itself
            return buildSucceeded(lower) && (
                lower.contains("verified") ||
                lower.contains("verification successful") ||
                lower.contains("o.k.") ||
                lower.contains("running...") && lower.contains("success")
            )
        }
    }

    private func buildSucceeded(_ lower: String) -> Bool {
        lower.contains("linking") ||
        lower.contains("completed") ||
        lower.contains("success") ||
        lower.contains("nothing to be done") ||
        lower.contains("report written") ||
        lower.contains("arm-none-eabi-size") ||
        lower.contains("tiarmsize") ||
        lower.contains("tiarmobjcopy")
    }
}
