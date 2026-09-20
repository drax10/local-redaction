import Foundation

enum TextSpanLocator {
    private static let locale = Locale(identifier: "es_MX")

    /// Collapses whitespace and case-folds so ALL-CAPS headers match body text.
    static func normalized(_ text: String) -> String {
        text.split { $0.isWhitespace }
            .joined(separator: " ")
            .lowercased(with: locale)
    }

    /// Finds every occurrence of `needle` in `haystack`, treating any whitespace
    /// (spaces, tabs, PDF line breaks) as interchangeable and ignoring case.
    static func nsRanges(of needle: String, in haystack: String) -> [NSRange] {
        let tokens = needle.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let pattern = tokens
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let fullRange = NSRange(haystack.startIndex..., in: haystack)
        return regex.matches(in: haystack, options: [], range: fullRange).map(\.range)
    }

    static func exactSubstrings(of needle: String, in haystack: String) -> [String] {
        nsRanges(of: needle, in: haystack).compactMap { range in
            Range(range, in: haystack).map { String(haystack[$0]) }
        }
    }
}
