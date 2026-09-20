import Foundation

/// An intermediate span produced by either extraction layer before tagging.
struct ExtractedMatch: Sendable, Hashable {
    let text: String
    let type: PIIType
    let nsRange: NSRange
}
