enum BuildAction: String, CaseIterable {
    case build = "build"
    case flash = "flash"
    case buildAndFlash = "all"
    case verify = "verify"

    var cliValue: String { rawValue }

    var displayName: String {
        switch self {
        case .build: return "仅编译"
        case .flash: return "仅烧录"
        case .buildAndFlash: return "编译并烧录"
        case .verify: return "验证连接"
        }
    }
}
