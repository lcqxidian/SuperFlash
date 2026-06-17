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

    func run(script: URL, project: URL, action: BuildAction, envOverrides: [String: String] = [:], extraArguments: [String] = []) {
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
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
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

        // 清理孤儿进程：切换项目时旧脚本被杀，其子进程 OpenOCD/DSLite/JLink
        // 仍可能占用调试接口，导致下次烧录失败
        for tool in ["openocd", "DSLite", "JLinkExe", "xdsdfu"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-f", tool]
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// 烧录前探针预热：独立连接一次后断开，清空探针内部状态机
    func warmupProbe(vendor: ProjectVendor) {
        print("[warmupProbe] vendor=\(vendor)")
        switch vendor {
        case .stm32:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/openocd")
            task.arguments = ["-f", "interface/stlink.cfg", "-f", "target/stm32f4x.cfg",
                              "-c", "adapter speed 4000", "-c", "init; reset sysresetreq; exit"]
            try? task.run()
            task.waitUntilExit()
            print("[warmupProbe] openocd done")
        case .tiMSPM0:
            // Search JLinkExe in common locations + PATH + user's known install
            let jlinkCandidates = [
                URL(fileURLWithPath: "/Users/lcq/SEGGER_JLink_V950/JLinkExe"),
                URL(fileURLWithPath: "/opt/homebrew/bin/JLinkExe"),
                URL(fileURLWithPath: "/usr/local/bin/JLinkExe"),
            ] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .components(separatedBy: ":")
                .map { URL(fileURLWithPath: $0).appendingPathComponent("JLinkExe") }
            guard let jlink = jlinkCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                print("[warmupProbe] JLinkExe not found")
                return
            }
            print("[warmupProbe] JLinkExe found: \(jlink.path)")
            let warmup = Process()
            warmup.executableURL = jlink
            warmup.arguments = ["-NoGui", "1", "-If", "SWD", "-Speed", "4000",
                                "-Device", "UNKNOWN",
                                "-CommandFile", "/dev/stdin"]
            let input = Pipe()
            warmup.standardInput = input
            try? input.fileHandleForWriting.write(contentsOf: "connect\nexit\n".data(using: .utf8)!)
            try? input.fileHandleForWriting.close()
            let outPipe = Pipe()
            warmup.standardOutput = outPipe
            warmup.standardError = outPipe
            try? warmup.run()
            warmup.waitUntilExit()
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("[warmupProbe] JLink warmup done, rc=\(warmup.terminationStatus), out=\(out.prefix(200))")
        case .unknown:
            print("[warmupProbe] unknown vendor, skipping")
        }
    }
}
