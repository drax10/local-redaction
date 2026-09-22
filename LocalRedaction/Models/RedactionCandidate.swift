import Foundation

struct RedactionCandidate: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let originalText: String
    var type: PIIType
    var isSelected: Bool

    init(
        id: UUID = UUID(),
        originalText: String,
        type: PIIType,
        isSelected: Bool = true
    ) {
        self.id = id
        self.originalText = originalText
        self.type = type
        self.isSelected = isSelected
    }
}
