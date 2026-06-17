enum STM32Family: String, Codable {
    case f1
    case f4
    case unknown

    var cpuFlags: [String] {
        switch self {
        case .f1:
            return ["-mcpu=cortex-m3", "-mthumb"]
        case .f4:
            return ["-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard"]
        case .unknown:
            return ["-mthumb"]
        }
    }

    var openOCDTarget: String {
        switch self {
        case .f1: return "target/stm32f1x.cfg"
        case .f4: return "target/stm32f4x.cfg"
        case .unknown: return "target/stm32f4x.cfg"
        }
    }
}
