import Foundation

enum RedactionEngine {
    /// Tags numbered in document order among currently selected items of each type.
    /// Deselected rows use a dash and are skipped in the count.
    static func numberedTags(for candidates: [RedactionCandidate]) -> [UUID: String] {
        var counters: [PIIType: Int] = [:]
        var tags: [UUID: String] = [:]

        for candidate in candidates {
            if candidate.isSelected {
                let next = (counters[candidate.type] ?? 0) + 1
                counters[candidate.type] = next
                tags[candidate.id] = "[\(candidate.type.tagLabel) \(next)]"
            } else {
                tags[candidate.id] = "[\(candidate.type.tagLabel) -]"
            }
        }

        return tags
    }

    /// Replaces selected candidates with their numbered tags. Whitespace and PDF
    /// line breaks inside a span are treated as interchangeable so a wrapped
    /// address still redacts.
    static func redact(text: String, candidates: [RedactionCandidate]) -> String {
        var index = RedactionIndex()
        index.synchronize(token: "ad-hoc", text: text, candidates: candidates)
        return index.apply(
            text: text,
            tags: numberedTags(for: candidates),
            selectedIDs: Set(candidates.filter(\.isSelected).map(\.id))
        )
    }

    fileprivate static func streetNumberCore(from address: String) -> String? {
        let normalized = TextSpanLocator.normalized(address)
        let pattern = #"(?i)(?:Calle|Avenida|Av\.|Boulevard|Blvd\.|Paseo|Calzada|Privada)\s+.+?\s+\d+[A-Za-z\-]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let range = Range(match.range, in: normalized) else {
            return nil
        }
        let core = String(normalized[range])
        return core.count >= 12 ? core : nil
    }

    fileprivate static func expandTrailingAddressDetails(_ range: NSRange, in text: String) -> NSRange {
        let pattern = #"(?:,?\s*(?:C\.?P\.?\s*\d{5}|C[oó]digo\s+Postal\s*\d{5}|Col(?:onia)?\.?\s+[^,.]{2,40}|Depto\.?\s*[\w\-]+|Despacho\s+\d+|Piso\s+\d+|Alcald[ií]a\s+[^,.]{2,40}|Ciudad de México|Estado de México))+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let stringRange = Range(range, in: text) else {
            return range
        }

        let tail = String(text[stringRange.upperBound...])
        let tailNSRange = NSRange(tail.startIndex..., in: tail)
        guard let match = regex.firstMatch(in: tail, options: [.anchored], range: tailNSRange) else {
            return range
        }
        return NSRange(location: range.location, length: range.length + match.range.length)
    }
}

/// Locates each candidate once in the source text. Toggling Incluir only reapplies
/// those cached ranges — it does not scan the document again.
struct RedactionIndex: Sendable {
    private var token = ""
    private var utf16Length = -1
    private var spans: [Span] = []

    private struct Span: Sendable {
        var id: UUID
        var type: PIIType
        var ranges: [NSRange]
    }

    mutating func synchronize(token: String, text: String, candidates: [RedactionCandidate]) {
        let length = (text as NSString).length
        if token != self.token || length != utf16Length {
            self.token = token
            utf16Length = length
            spans = candidates.map { Self.makeSpan(for: $0, in: text) }
            return
        }

        let existing = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        var next: [Span] = []
        next.reserveCapacity(candidates.count)
        for candidate in candidates {
            if let span = existing[candidate.id], span.type == candidate.type {
                next.append(span)
            } else {
                next.append(Self.makeSpan(for: candidate, in: text))
            }
        }
        spans = next
    }

    func apply(text: String, tags: [UUID: String], selectedIDs: Set<UUID>) -> String {
        let nsText = text as NSString
        var replacements: [(NSRange, String)] = []
        for span in spans where selectedIDs.contains(span.id) {
            guard let tag = tags[span.id] else { continue }
            for range in span.ranges where range.location + range.length <= nsText.length {
                replacements.append((range, tag))
            }
        }

        replacements.sort { lhs, rhs in
            if lhs.0.location == rhs.0.location {
                return lhs.0.length > rhs.0.length
            }
            return lhs.0.location < rhs.0.location
        }

        let output = NSMutableString(capacity: nsText.length)
        var cursor = 0
        for (range, tag) in replacements {
            if range.location < cursor { continue }
            if range.location > cursor {
                output.append(nsText.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            output.append(tag)
            cursor = range.location + range.length
        }
        if cursor < nsText.length {
            output.append(nsText.substring(from: cursor))
        }
        return output as String
    }

    private static func makeSpan(for candidate: RedactionCandidate, in text: String) -> Span {
        var ranges = TextSpanLocator.nsRanges(of: candidate.originalText, in: text)
        if candidate.type == .address {
            ranges = ranges.map { RedactionEngine.expandTrailingAddressDetails($0, in: text) }
            if let core = RedactionEngine.streetNumberCore(from: candidate.originalText) {
                for coreRange in TextSpanLocator.nsRanges(of: core, in: text) {
                    let covered = ranges.contains { NSIntersectionRange($0, coreRange).length == coreRange.length }
                    if !covered {
                        ranges.append(RedactionEngine.expandTrailingAddressDetails(coreRange, in: text))
                    }
                }
            }
        }
        ranges.sort { $0.location < $1.location }
        return Span(id: candidate.id, type: candidate.type, ranges: ranges)
    }
}
