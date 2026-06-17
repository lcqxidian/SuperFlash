enum ProjectKind: String, Codable {
    case keil = "Keil"
    case bareFolder = "Bare Folder"
    case makefile = "Makefile"
    case cubeIDE = "CubeIDE"
    case ccsSysConfig = "CCS/SysConfig"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .keil: return "Keil 项目"
        case .bareFolder: return "裸文件夹"
        case .makefile: return "Makefile 项目"
        case .cubeIDE: return "CubeIDE 项目"
        case .ccsSysConfig: return "CCS/SysConfig 项目"
        case .unknown: return "未知"
        }
    }
}
