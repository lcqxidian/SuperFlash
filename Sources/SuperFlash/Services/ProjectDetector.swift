import Foundation

struct ProjectDetector {

    private let ignoredDirs: Set<String> = [
        ".git", ".svn", "build", "Debug", "Release",
        "codex_build", "DerivedData", "node_modules", "__pycache__",
        ".settings", ".clangd", ".metadata"
    ]

    private let scanMaxDepth = 8

    func detectProject(at url: URL) -> ProjectInfo {
        var info = ProjectInfo(rootURL: url)

        let stm32Score = scoreSTM32(at: url)
        let tiScore = scoreTI(at: url)

        if stm32Score > tiScore && stm32Score > 0 {
            info.vendor = .stm32
            info = detectSTM32Details(info, at: url)
        } else if tiScore > 0 {
            info.vendor = .tiMSPM0
            info = detectTIDetails(info, at: url)
        } else {
            info.vendor = .unknown
            info.projectKind = .unknown
        }

        info.sourceCount = countSources(at: url)
        info.includeCount = countIncludes(at: url)
        return info
    }

    // MARK: - STM32 Scoring

    private func scoreSTM32(at url: URL) -> Int {
        var score = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth {
                enumerator?.skipDescendants()
                continue
            }
            let filename = fileURL.lastPathComponent
            if ignoredDirs.contains(filename) {
                enumerator?.skipDescendants()
                continue
            }

            if filename.hasSuffix(".ioc") { score += 5 }
            else if filename.hasSuffix(".uvprojx") || filename.hasSuffix(".uvproj") { score += 4 }
            else if filename.hasPrefix("startup_stm32") && (filename.hasSuffix(".s") || filename.hasSuffix(".S")) { score += 4 }
            else if filename.hasPrefix("STM32") && filename.hasSuffix(".ld") { score += 3 }
            else if filename == "Makefile" || filename == "makefile" { score += 1 }
            else if filename == "main.c" { score += 1 }
            else if filename.hasPrefix("stm32") && filename.hasSuffix(".h") { score += 2 }
        }
        return score
    }

    // MARK: - TI MSPM0 Scoring

    private func scoreTI(at url: URL) -> Int {
        var score = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth {
                enumerator?.skipDescendants()
                continue
            }
            let filename = fileURL.lastPathComponent
            if ignoredDirs.contains(filename) && filename != "Debug" {
                enumerator?.skipDescendants()
                continue
            }

            if filename == "empty.syscfg" || filename.hasSuffix(".syscfg") { score += 4 }
            else if fileURL.path.contains("targetConfigs/") && filename.hasPrefix("MSPM0") && filename.hasSuffix(".ccxml") { score += 5 }
            else if filename == "ti_msp_dl_config.c" || filename == "ti_msp_dl_config.h" { score += 4 }
            else if filename == "device_linker.cmd" { score += 3 }
            else if fileURL.path.contains(".ccsproject") || fileURL.path.contains(".cproject") { score += 2 }
            else if filename.contains("MSPM0") { score += 2 }
            else if filename == "Makefile" || filename == "makefile" { score += 1 }
        }
        return score
    }

    // MARK: - STM32 Details

    private func detectSTM32Details(_ info: ProjectInfo, at url: URL) -> ProjectInfo {
        var result = info

        result.projectKind = detectSTM32ProjectKind(at: url)
        result.chipName = detectSTM32Chip(at: url)
        if let chip = result.chipName {
            result.stm32Family = familyFromChip(chip)
        }
        result.makefile = findFile(at: url, name: "Makefile") ?? findFile(at: url, name: "makefile")
        result.keilProject = findFile(at: url, extensions: ["uvprojx", "uvproj"])
        result.iocFile = findFile(at: url, extensions: ["ioc"])
        result.linkerScript = findFile(at: url, pattern: "STM32*.ld")
        result.startupFile = findFile(at: url, pattern: "startup_stm32*")
        result.mainFiles = findAllFiles(at: url, name: "main.c")

        return result
    }

    private func detectSTM32ProjectKind(at url: URL) -> ProjectKind {
        if hasFile(at: url, extensions: ["uvprojx", "uvproj"]) { return .keil }
        if hasFile(at: url, name: "Makefile") || hasFile(at: url, name: "makefile") { return .makefile }
        if hasFile(at: url, extensions: ["ioc"]) && dirExists(at: url, name: "Core") { return .cubeIDE }
        if hasFile(at: url, name: "main.c") { return .bareFolder }
        return .unknown
    }

    private func detectSTM32Chip(at url: URL) -> String? {
        if let ioc = findFile(at: url, extensions: ["ioc"]),
           let content = try? String(contentsOf: ioc, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("Mcu.Name=") {
                    return normalizeMCU(String(line.dropFirst(9)))
                }
            }
        }

        if let uvprojx = findFile(at: url, extensions: ["uvprojx"]),
           let content = try? String(contentsOf: uvprojx, encoding: .utf8) {
            if let range = content.range(of: "<Device>"),
               let endRange = content[range.upperBound...].range(of: "</Device>") {
                let device = String(content[range.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !device.isEmpty { return normalizeMCU(device) }
            }
        }

        if let ld = findFile(at: url, pattern: "STM32*.ld") {
            let name = ld.lastPathComponent
                .replacingOccurrences(of: "_FLASH.ld", with: "")
                .replacingOccurrences(of: ".ld", with: "")
            if name.hasPrefix("STM32") { return normalizeMCU(name) }
        }

        if let startup = findFile(at: url, pattern: "startup_stm32*") {
            let name = startup.lastPathComponent.lowercased()
            if name.contains("f40_41xxx") || name.contains("f4") { return "STM32F407ZG" }
            if name.contains("f10x") || name.contains("f1") { return "STM32F103C8" }
        }

        let sourceFiles = findAllFiles(at: url, extensions: ["c", "h"])
        for file in sourceFiles.prefix(50) {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if content.contains("STM32F40_41xxx") { return "STM32F407ZG" }
            if content.contains("STM32F10X_HD") || content.contains("STM32F10X_MD") { return "STM32F103C8" }
            if content.contains("STM32F103") { return "STM32F103C8" }
            if content.contains("STM32F407") { return "STM32F407ZG" }
        }

        if url.lastPathComponent.uppercased().contains("F4") { return "STM32F407ZG" }
        if url.lastPathComponent.uppercased().contains("F1") { return "STM32F103C8" }

        return nil
    }

    // MARK: - TI MSPM0 Details

    private func detectTIDetails(_ info: ProjectInfo, at url: URL) -> ProjectInfo {
        var result = info
        result.projectKind = detectTIProjectKind(at: url)
        result.chipName = detectTIChip(at: url)
        result.syscfgFile = findFile(at: url, name: "empty.syscfg") ?? findFile(at: url, extensions: ["syscfg"])
        result.tiLinkerCmd = findFile(at: url, name: "device_linker.cmd", subdir: "Debug")
        result.tiConfigFile = findFile(at: url, pattern: "MSPM0*.ccxml", subdir: "targetConfigs")
        result.mainFiles = findAllFiles(at: url, name: "empty.c") + findAllFiles(at: url, name: "main.c")
        return result
    }

    private func detectTIProjectKind(at url: URL) -> ProjectKind {
        if hasFile(at: url, name: "ti_msp_dl_config.c", subdir: "Debug") &&
           hasFile(at: url, name: "device_linker.cmd", subdir: "Debug") { return .ccsSysConfig }
        if hasFile(at: url, extensions: ["syscfg"]) { return .ccsSysConfig }
        if hasFile(at: url, name: "Makefile") || hasFile(at: url, name: "makefile") { return .makefile }
        return .unknown
    }

    private func detectTIChip(at url: URL) -> String? {
        let ccxmlFiles = findAllFiles(at: url, pattern: "MSPM0*.ccxml", subdir: "targetConfigs")
        for file in ccxmlFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                if let match = content.range(of: #"MSPM0[A-Z0-9]+"#, options: .regularExpression) {
                    return String(content[match])
                }
            }
        }

        let configFiles = findAllFiles(at: url, name: "ti_msp_dl_config.h")
        for file in configFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                if let match = content.range(of: #"__MSPM0[A-Z0-9]+__"#, options: .regularExpression) {
                    return String(content[match]).replacingOccurrences(of: "_", with: "")
                }
                if let match = content.range(of: #"MSPM0[A-Z0-9]+"#, options: .regularExpression) {
                    return String(content[match])
                }
            }
        }

        let syscfgFiles = findAllFiles(at: url, extensions: ["syscfg"])
        for file in syscfgFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                if let match = content.range(of: #"MSPM0[A-Z0-9]+"#, options: .regularExpression) {
                    return String(content[match])
                }
            }
        }

        if url.lastPathComponent.uppercased().contains("MSPM0G3507") { return "MSPM0G3507" }
        if url.lastPathComponent.uppercased().contains("MSPM0") { return "MSPM0G3507" }

        return nil
    }

    // MARK: - Helpers

    private func normalizeMCU(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_FLASH", with: "")
            .replacingOccurrences(of: "_", with: "")
            .uppercased()
    }

    private func familyFromChip(_ chip: String) -> STM32Family {
        let upper = chip.uppercased()
        if upper.contains("STM32F4") || upper.contains("STM32F4041") { return .f4 }
        if upper.contains("STM32F1") || upper.contains("STM32F10X") { return .f1 }
        return .unknown
    }

    private func hasFile(at url: URL, extensions: [String]) -> Bool {
        findFile(at: url, extensions: extensions) != nil
    }

    private func hasFile(at url: URL, name: String, subdir: String? = nil) -> Bool {
        findFile(at: url, name: name, subdir: subdir) != nil
    }

    private func findFile(at url: URL, extensions: [String]) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if ignoredDirs.contains(fileURL.lastPathComponent) { enumerator?.skipDescendants(); continue }
            if extensions.contains(fileURL.pathExtension.lowercased()) { return fileURL }
        }
        return nil
    }

    private func findFile(at url: URL, name: String, subdir: String? = nil) -> URL? {
        let searchURL = subdir.flatMap { url.appendingPathComponent($0) } ?? url
        let enumerator = FileManager.default.enumerator(
            at: searchURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if fileURL.lastPathComponent == name { return fileURL }
            if ignoredDirs.contains(fileURL.lastPathComponent) && fileURL.lastPathComponent != "Debug" { enumerator?.skipDescendants() }
        }
        return nil
    }

    private func findFile(at url: URL, pattern: String, subdir: String? = nil) -> URL? {
        let searchURL = subdir.flatMap { url.appendingPathComponent($0) } ?? url
        let enumerator = FileManager.default.enumerator(
            at: searchURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if wildcardMatch(fileURL.lastPathComponent, pattern: pattern) { return fileURL }
            if ignoredDirs.contains(fileURL.lastPathComponent) && fileURL.lastPathComponent != "Debug" { enumerator?.skipDescendants() }
        }
        return nil
    }

    private func findAllFiles(at url: URL, name: String, subdir: String? = nil) -> [URL] {
        var results: [URL] = []
        let searchURL = subdir.flatMap { url.appendingPathComponent($0) } ?? url
        let enumerator = FileManager.default.enumerator(
            at: searchURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if fileURL.lastPathComponent == name { results.append(fileURL) }
            if ignoredDirs.contains(fileURL.lastPathComponent) && fileURL.lastPathComponent != "Debug" { enumerator?.skipDescendants() }
        }
        return results
    }

    private func findAllFiles(at url: URL, pattern: String, subdir: String? = nil) -> [URL] {
        var results: [URL] = []
        let searchURL = subdir.flatMap { url.appendingPathComponent($0) } ?? url
        let enumerator = FileManager.default.enumerator(
            at: searchURL, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if wildcardMatch(fileURL.lastPathComponent, pattern: pattern) { results.append(fileURL) }
            if ignoredDirs.contains(fileURL.lastPathComponent) && fileURL.lastPathComponent != "Debug" { enumerator?.skipDescendants() }
        }
        return results
    }

    private func findAllFiles(at url: URL, extensions: [String]) -> [URL] {
        var results: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if ignoredDirs.contains(fileURL.lastPathComponent) { enumerator?.skipDescendants(); continue }
            if extensions.contains(fileURL.pathExtension.lowercased()) { results.append(fileURL) }
        }
        return results
    }

    private func dirExists(at url: URL, name: String) -> Bool {
        let dir = url.appendingPathComponent(name)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func countSources(at url: URL) -> Int {
        var count = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if ignoredDirs.contains(fileURL.lastPathComponent) { enumerator?.skipDescendants(); continue }
            if fileURL.pathExtension == "c" || fileURL.pathExtension == "s" || fileURL.pathExtension == "S" {
                count += 1
            }
        }
        return count
    }

    private func countIncludes(at url: URL) -> Int {
        var count = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let depth = enumerator?.level, depth > scanMaxDepth { enumerator?.skipDescendants() }
            if ignoredDirs.contains(fileURL.lastPathComponent) { enumerator?.skipDescendants(); continue }
            if fileURL.pathExtension == "h" { count += 1 }
        }
        return count
    }

    private func wildcardMatch(_ value: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        return value.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
