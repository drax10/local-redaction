import Foundation

struct CachedDocumentSummary: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var fileName: String
    var fileHash: String
    var processedAt: Date
    var updatedAt: Date
    var candidateCount: Int
    var searchPreview: String

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return fileName.lowercased().contains(needle) || searchPreview.contains(needle)
    }

    var systemImage: String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "doc", "docx": "doc.text"
        default: "doc.plaintext"
        }
    }
}

struct CachedDocumentRecord: Codable, Sendable {
    var summary: CachedDocumentSummary
    var originalText: String
    var candidates: [RedactionCandidate]
}

struct DuplicateScanPrompt: Identifiable {
    var id: UUID { existing.id }
    let url: URL
    let existing: CachedDocumentSummary
}
