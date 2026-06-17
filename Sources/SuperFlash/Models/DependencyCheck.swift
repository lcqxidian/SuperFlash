import Foundation

enum DependencyStatus: String, Codable {
    case ok = "OK"
    case warning = "Warning"
    case missing = "Missing"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .ok: return "正常"
        case .warning: return "警告"
        case .missing: return "缺失"
        case .unknown: return "未知"
        }
    }
}

struct DependencyCheck: Identifiable {
    let id: UUID
    var name: String
    var status: DependencyStatus
    var path: URL?
    var message: String

    init(id: UUID = UUID(), name: String, status: DependencyStatus = .unknown, path: URL? = nil, message: String = "") {
        self.id = id
        self.name = name
        self.status = status
        self.path = path
        self.message = message
    }
}
