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
    /// Alphanumeric tokens are bounded so "de" does not match inside "departamento".
    static func nsRanges(of needle: String, in haystack: String) -> [NSRange] {
        let tokens = needle.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let pattern = tokens.map(boundedPattern(for:)).joined(separator: #"\s+"#)

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

    private static func boundedPattern(for token: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let startsAlnum = token.first?.isLetter == true || token.first?.isNumber == true
        let endsAlnum = token.last?.isLetter == true || token.last?.isNumber == true
        return "\(startsAlnum ? #"\b"# : "")\(escaped)\(endsAlnum ? #"\b"# : "")"
    }
}
