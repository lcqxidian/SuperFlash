enum ProjectVendor: String, Codable, CaseIterable {
    case stm32 = "STM32"
    case tiMSPM0 = "TI MSPM0"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .stm32: return "STM32"
        case .tiMSPM0: return "TI MSPM0"
        case .unknown: return "未知"
        }
    }
}
