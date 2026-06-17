import Foundation

struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let text: String

    init(id: UUID = UUID(), timestamp: Date = Date(), text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}
