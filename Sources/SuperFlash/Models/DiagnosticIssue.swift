import Foundation

struct DiagnosticIssue: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var suggestion: String

    init(id: UUID = UUID(), title: String, detail: String, suggestion: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
    }
}
