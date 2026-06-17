enum RunState: Equatable {
    case idle
    case detecting
    case checkingEnvironment
    case building
    case flashing
    case verifying
    case success
    case failed(String)
    case cancelled

    var inProgress: Bool {
        switch self {
        case .idle, .success, .failed, .cancelled:
            return false
        case .detecting, .checkingEnvironment, .building, .flashing, .verifying:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "就绪"
        case .detecting: return "检测项目中..."
        case .checkingEnvironment: return "检查环境中..."
        case .building: return "编译中..."
        case .flashing: return "烧录中..."
        case .verifying: return "验证中..."
        case .success: return "成功"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var failureReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}
