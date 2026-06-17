import Foundation

actor EnvironmentChecker {
    func checkAll(
        armGccOverride: String = "",
        openocdOverride: String = "",
        tiArmClangOverride: String = "",
        mspm0SDKOverride: String = "",
        jlinkOverride: String = ""
    ) -> ToolchainInfo {
        var info = ToolchainInfo()

        // ARM GCC: user override first, then auto-detect
        if !armGccOverride.isEmpty {
            let url = URL(fileURLWithPath: armGccOverride)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                info.armGcc = url
            }
        }
        if info.armGcc == nil {
            info.armGcc = findExec("arm-none-eabi-gcc", extraPaths: [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                NSHomeDirectory() + "/arm-gcc-toolchain/bin"
            ])
        }
        if info.armGcc != nil {
            let dir = info.armGcc!.deletingLastPathComponent().path
            info.armObjcopy = findExec("arm-none-eabi-objcopy", extraPaths: [dir])
            if info.armObjcopy == nil {
                info.armObjcopy = findExec("arm-none-eabi-objcopy")
            }
            info.armSize = findExec("arm-none-eabi-size", extraPaths: [dir])
            if info.armSize == nil {
                info.armSize = findExec("arm-none-eabi-size")
            }
        }

        // OpenOCD: user override first
        if !openocdOverride.isEmpty {
            let url = URL(fileURLWithPath: openocdOverride)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                info.openocd = url
            }
        }
        if info.openocd == nil {
            info.openocd = findExec("openocd", extraPaths: ["/opt/homebrew/bin", "/usr/local/bin"])
        }
        info.stlinkConnected = detectSTLink()

        // TI Arm Clang
        if !tiArmClangOverride.isEmpty {
            info.tiArmClang = resolveTIArmClangOverride(tiArmClangOverride)
        }
        if info.tiArmClang == nil {
            info.tiArmClang = findTIArmClang()
        }
        if info.tiArmClang != nil {
            let dir = info.tiArmClang!.deletingLastPathComponent().path
            info.tiObjcopy = findExec("tiarmobjcopy", extraPaths: [dir])
            info.tiSize = findExec("tiarmsize", extraPaths: [dir])
        }

        // MSPM0 SDK
        if !mspm0SDKOverride.isEmpty {
            let url = URL(fileURLWithPath: mspm0SDKOverride)
            let requiredPaths = [
                "source/ti/devices/msp/m0p/startup_system_files/ticlang",
                "source/ti/driverlib/lib/ticlang/m0p"
            ]
            var valid = true
            for rp in requiredPaths {
                if !FileManager.default.fileExists(atPath: url.appendingPathComponent(rp).path) {
                    valid = false
                    break
                }
            }
            if valid { info.mspm0SDK = url }
        }
        if info.mspm0SDK == nil {
            info.mspm0SDK = findMSPM0SDK()
        }

        // J-Link
        if !jlinkOverride.isEmpty {
            let url = URL(fileURLWithPath: jlinkOverride)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                info.jlinkExe = url
            }
        }
        if info.jlinkExe == nil {
            info.jlinkExe = findJLink()
        }
        info.jlinkConnected = detectJLink()

        return info
    }

    // MARK: - Find Executables

    private func findExec(_ name: String, extraPaths: [String] = []) -> URL? {
        var candidates: [String] = extraPaths
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: pathEnv.components(separatedBy: ":"))
        }
        for dir in candidates {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        let which = whichShell(name)
        if let w = which { return URL(fileURLWithPath: w) }
        return nil
    }

    private func whichShell(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findTIArmClang() -> URL? {
        let base = "/Applications/ti"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            return findExec("tiarmclang")
        }
        for dir in dirs {
            if dir.hasPrefix("ccstheia") || dir.hasPrefix("ccs") {
                let compilerBase = "\(base)/\(dir)/ccs/tools/compiler"
                guard let compilers = try? FileManager.default.contentsOfDirectory(atPath: compilerBase) else { continue }
                for comp in compilers {
                    if comp.hasPrefix("ti-cgt-armllvm") {
                        let exe = "\(compilerBase)/\(comp)/bin/tiarmclang"
                        if FileManager.default.isExecutableFile(atPath: exe) {
                            return URL(fileURLWithPath: exe)
                        }
                    }
                }
            }
        }
        return findExec("tiarmclang")
    }

    private func findMSPM0SDK() -> URL? {
        let base = "/Applications/ti"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return nil }
        let sdkDirs = dirs.filter { $0.hasPrefix("mspm0_sdk_") }.sorted()
        for dir in sdkDirs.reversed() {
            let sdkURL = URL(fileURLWithPath: "\(base)/\(dir)")
            let requiredPaths = [
                "source/ti/devices/msp/m0p/startup_system_files/ticlang",
                "source/ti/driverlib/lib/ticlang/m0p"
            ]
            var allFound = true
            for rp in requiredPaths {
                if !FileManager.default.fileExists(atPath: sdkURL.appendingPathComponent(rp).path) {
                    allFound = false
                    break
                }
            }
            if allFound { return sdkURL }
        }
        return nil
    }

    private func findJLink() -> URL? {
        let candidates = [
            NSHomeDirectory() + "/SEGGER_JLink_V950/JLinkExe",
            "/Applications/SEGGER/JLink/JLinkExe",
            "/usr/local/bin/JLinkExe",
            "/opt/homebrew/bin/JLinkExe",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return findExec("JLinkExe")
    }

    private func resolveTIArmClangOverride(_ value: String) -> URL? {
        let url = URL(fileURLWithPath: value)
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        let directBin = url.appendingPathComponent("tiarmclang")
        if FileManager.default.isExecutableFile(atPath: directBin.path) {
            return directBin
        }

        let nestedBin = url.appendingPathComponent("bin/tiarmclang")
        if FileManager.default.isExecutableFile(atPath: nestedBin.path) {
            return nestedBin
        }

        return nil
    }

    // MARK: - Hardware Detection

    private func detectSTLink() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-p", "IOUSB", "-l", "-w0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let keywords = ["ST-LINK", "STLink", "STMicroelectronics", "STM32 STLink"]
        return keywords.contains { output.contains($0) }
    }

    private func detectJLink() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-p", "IOUSB", "-l", "-w0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let keywords = ["J-Link", "SEGGER"]
        return keywords.contains { output.contains($0) }
    }
}
