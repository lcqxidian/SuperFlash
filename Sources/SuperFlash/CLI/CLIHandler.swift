import Foundation

/// CLI 模式：AI/脚本可通过命令行直接调用编译烧录
/// 用法：
///   SuperFlash build /path/to/project
///   SuperFlash flash /path/to/project
///   SuperFlash build-flash /path/to/project
///   SuperFlash verify /path/to/project
struct CLIHandler {
    enum Action: String {
        case build, flash, buildFlash = "build-flash", verify
    }

    let action: Action
    let projectPath: URL

    static func parse(_ args: [String]) -> CLIHandler? {
        guard args.count >= 3 else { return nil }
        guard let action = Action(rawValue: args[1]) else { return nil }
        var url = URL(fileURLWithPath: args[2])
        if args.count > 3 {
            // Join remaining args as project path (handle spaces)
            let path = args[2...].joined(separator: " ")
            url = URL(fileURLWithPath: path)
        }
        return CLIHandler(action: action, projectPath: url)
    }

    static func printUsage() {
        print("SuperFlash CLI")
        print("  编译：  \(CommandLine.arguments[0]) build /path/to/project")
        print("  烧录：  \(CommandLine.arguments[0]) flash /path/to/project")
        print("  编+烧： \(CommandLine.arguments[0]) build-flash /path/to/project")
        print("  验证：  \(CommandLine.arguments[0]) verify /path/to/project")
    }

    func run() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectPath.path) else {
            throw CLIError.projectNotFound(projectPath.path)
        }
        let scripts = findScripts()
        let vendor = detectVendor()
        let script = vendor == "ti" ? scripts.ti : scripts.stm32
        let actionStr: String
        switch action {
        case .build:      actionStr = "build"
        case .flash:      actionStr = "flash"
        case .buildFlash: actionStr = "all"
        case .verify:     actionStr = "verify"
        }

        print("[SuperFlash CLI] \(vendor.uppercased()) \(actionStr) → \(projectPath.path)")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script.path, projectPath.path, "--action", actionStr]
        proc.environment = ["PATH": "/usr/bin:/usr/local/bin:/opt/homebrew/bin:\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            throw CLIError.commandFailed(exitCode: proc.terminationStatus)
        }
        print("[SuperFlash CLI] 完成")
    }

    private func detectVendor() -> String {
        let fm = FileManager.default
        // TI MSPM0 检测
        let ccxmls = (try? fm.contentsOfDirectory(at: projectPath, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "ccxml" } ?? []
        if !ccxmls.isEmpty || fm.fileExists(atPath: projectPath.appendingPathComponent("empty.syscfg").path) {
            return "ti"
        }
        // STM32 检测
        let iocFiles = (try? fm.contentsOfDirectory(at: projectPath, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "ioc" } ?? []
        if !iocFiles.isEmpty ||
            fm.fileExists(atPath: projectPath.appendingPathComponent("DRIVE/stm32_mcu").path) ||
            fm.fileExists(atPath: projectPath.appendingPathComponent("DRIVE/CMSIS").path) {
            return "stm32"
        }
        // 先尝试 STM32（默认）
        return "stm32"
    }

    private func findScripts() -> (stm32: URL, ti: URL) {
        let resources = Bundle.main.resourceURL!
        return (
            resources.appendingPathComponent("scripts/stm32_build_flash.py"),
            resources.appendingPathComponent("scripts/ti_mspm0_build_flash.py")
        )
    }
}

enum CLIError: LocalizedError {
    case projectNotFound(String)
    case commandFailed(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let p): return "项目不存在：\(p)"
        case .commandFailed(let c):   return "命令失败，退出码 \(c)"
        }
    }
}
