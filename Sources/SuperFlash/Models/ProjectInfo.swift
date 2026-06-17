import Foundation

struct ProjectInfo: Codable, Identifiable, Equatable {
    var id: UUID
    var rootURL: URL
    var displayName: String
    var vendor: ProjectVendor
    var projectKind: ProjectKind
    var chipName: String?
    var stm32Family: STM32Family?

    var makefile: URL?
    var keilProject: URL?
    var iocFile: URL?
    var startupFile: URL?
    var linkerScript: URL?

    var syscfgFile: URL?
    var tiConfigFile: URL?
    var tiLinkerCmd: URL?

    var mainFiles: [URL]
    var sourceCount: Int
    var includeCount: Int

    init(
        id: UUID = UUID(),
        rootURL: URL,
        displayName: String? = nil,
        vendor: ProjectVendor = .unknown,
        projectKind: ProjectKind = .unknown,
        chipName: String? = nil,
        stm32Family: STM32Family? = nil
    ) {
        self.id = id
        self.rootURL = rootURL
        self.displayName = displayName ?? rootURL.lastPathComponent
        self.vendor = vendor
        self.projectKind = projectKind
        self.chipName = chipName
        self.stm32Family = stm32Family
        self.mainFiles = []
        self.sourceCount = 0
        self.includeCount = 0
    }

    var isDetected: Bool {
        vendor != .unknown
    }

    var buildMethod: String {
        switch vendor {
        case .stm32:
            if makefile != nil { return "现有 Makefile" }
            return "生成 GCC 编译"
        case .tiMSPM0:
            return "TI Arm Clang + SysConfig"
        case .unknown:
            return "未知"
        }
    }

    var flashMethod: String {
        switch vendor {
        case .stm32:
            return "OpenOCD + ST-Link"
        case .tiMSPM0:
            return "J-Link SWD"
        case .unknown:
            return "未知"
        }
    }

    var buildReady: Bool {
        vendor != .unknown
    }
}
