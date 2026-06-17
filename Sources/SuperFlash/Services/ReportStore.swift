import Foundation
import AppKit

struct ReportStore {
    private let fileManager = FileManager.default

    func reportURL(for project: URL, vendor: ProjectVendor) -> URL? {
        let codexBuild = project.appendingPathComponent("codex_build")
        let name: String
        switch vendor {
        case .stm32:
            name = "STM32_BUILD_FLASH_REPORT.md"
        case .tiMSPM0:
            name = "TI_BUILD_FLASH_REPORT.md"
        case .unknown:
            return nil
        }
        let url = codexBuild.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func openReport(for project: URL, vendor: ProjectVendor) -> Bool {
        guard let url = reportURL(for: project, vendor: vendor) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    func openCodexBuild(for project: URL) -> Bool {
        let url = project.appendingPathComponent("codex_build")
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    func openBuildArtifact(for project: URL, vendor: ProjectVendor) -> Bool {
        switch vendor {
        case .stm32:
            let candidates = [
                project.appendingPathComponent("build"),
                project.appendingPathComponent("codex_build/build-gcc")
            ]
            for url in candidates {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    NSWorkspace.shared.open(url)
                    return true
                }
            }
        case .tiMSPM0:
            let url = project.appendingPathComponent("codex_build/build-ticlang")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                NSWorkspace.shared.open(url)
                return true
            }
        case .unknown:
            break
        }
        return false
    }
}
