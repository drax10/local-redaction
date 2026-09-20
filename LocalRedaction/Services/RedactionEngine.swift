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
        let tags = numberedTags(for: candidates)
        let selected = candidates.filter(\.isSelected)

        var replacements: [(original: String, tag: String)] = []
        var seen = Set<String>()
        for candidate in selected {
            let key = TextSpanLocator.normalized(candidate.originalText)
            guard seen.insert("\(candidate.type.rawValue)|\(key)").inserted else { continue }
            guard let tag = tags[candidate.id] else { continue }
            replacements.append((candidate.originalText, tag))
        }

        replacements.sort { $0.original.count > $1.original.count }

        for candidate in selected where candidate.type == .address {
            if let core = streetNumberCore(from: candidate.originalText),
               let tag = tags[candidate.id] {
                let key = TextSpanLocator.normalized(core)
                if seen.insert("address-core|\(key)").inserted {
                    replacements.append((core, tag))
                }
            }
        }

        replacements.sort { $0.original.count > $1.original.count }

        var output = text
        for replacement in replacements {
            let ranges = TextSpanLocator.nsRanges(of: replacement.original, in: output)
            for range in ranges.reversed() {
                let expanded = expandTrailingAddressDetails(range, in: output)
                guard let stringRange = Range(expanded, in: output) else { continue }
                output.replaceSubrange(stringRange, with: replacement.tag)
            }
        }
        return output
    }

    /// "Calle X 105, Depto..., C.P. 06700" → "Calle X 105" so shorter repeats still redact.
    private static func streetNumberCore(from address: String) -> String? {
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

    private static func expandTrailingAddressDetails(_ range: NSRange, in text: String) -> NSRange {
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
