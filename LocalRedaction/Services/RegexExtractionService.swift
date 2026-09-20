import Foundation

/// Deterministic extractor for strict Mexican PII formats.
final class RegexExtractionService: Sendable {
    private let patterns: [(PIIType, NSRegularExpression)]

    init() {
        patterns = Self.compilePatterns()
    }

    func extract(from text: String) -> [ExtractedMatch] {
        let fullRange = NSRange(text.startIndex..., in: text)
        var accepted: [ExtractedMatch] = []

        for (type, regex) in patterns {
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for result in matches {
                let chosen = Self.preferredRange(in: result)
                guard chosen.location != NSNotFound,
                      let range = Range(chosen, in: text) else { continue }
                let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }

                let extracted = ExtractedMatch(text: value, type: type, nsRange: chosen)
                if accepted.contains(where: { Self.rangesOverlap($0.nsRange, extracted.nsRange) }) {
                    continue
                }
                accepted.append(extracted)
            }
        }

        return accepted.sorted { $0.nsRange.location < $1.nsRange.location }
    }

    /// Priority order matters: more specific identifiers are claimed first so they
    /// are not also reported as a weaker overlapping type (e.g. CURP vs RFC).
    private static func compilePatterns() -> [(PIIType, NSRegularExpression)] {
        let specs: [(PIIType, String, NSRegularExpression.Options)] = [
            (.curp, #"\b[A-Z][AEIOUX][A-Z]{2}\d{6}[HM][A-Z]{2}[B-DF-HJ-NP-TV-Z]{3}[A-Z0-9]\d\b"#, [.caseInsensitive]),
            // Before RFC: a Clave de Elector contains an RFC-shaped substring.
            (.identifier, #"\b[A-Z]{6}\d{8}[HM][A-Z0-9]{3}\b"#, [.caseInsensitive]),
            (.rfc, #"\b(?:[A-ZÑ&]{4}\d{6}[A-Z0-9]{3}|[A-ZÑ&]{3}\d{6}[A-Z0-9]{3})\b"#, [.caseInsensitive]),
            (.email, #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, [.caseInsensitive]),
            (.cedula, #"c[eé]dula\s+profesional(?:\s+n[uú]m(?:ero|\.)?)?\s*:?\s*\d{5,12}"#, [.caseInsensitive]),
            (
                .identifier,
                #"n[uú]mero de serie(?:\s*\(\s*VIN\s*\))?\s*:?\s*([A-HJ-NPR-Z0-9]{17})"#,
                [.caseInsensitive]
            ),
            (.identifier, #"\b\d{4}(?:[\s\-]\d{4}){3}\b"#, []),
            (
                .identifier,
                #"pasaporte(?:\s+mexicano)?\s*:?\s*([A-Z]\d{7,9})"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"(?:folio\s*\(\s*CIC\s*\)|\bCIC)\s*:?\s*(\d{12,13})"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"placas(?:\s+de\s+circulaci[oó]n)?\s+([A-Z]{3}[-\s]?\d{2,3}[-\s]?[A-Z0-9]{1,3})"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"nacid[oa]s?\s+el\s+\d{1,2}\s+de\s+[A-Za-zÁÉÍÓÚáéíóú]+\s+de\s+\d{4}(?:\s*\(\d{1,3}\s+a[nñ]os(?:\s+de\s+edad)?\))?"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"expediente\s*:?\s*\d{2,6}\s*/\s*\d{4}"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"escritura\s+p[uú]blica\s+n[uú]mero\s+(?:\d{1,3}(?:,\d{3})+|\d{2,8})"#,
                [.caseInsensitive]
            ),
            (.clabe, #"(?<!\d)\d{18}(?!\d)"#, []),
            (
                .phone,
                #"""
                (?:
                    \+52[\s\-.]*1?[\s\-.]*\d{2,3}[\s\-.]*\d{3,4}[\s\-.]*\d{4}
                    |
                    \(\d{2,3}\)[\s\-.]*\d{3,4}[\s\-.]*\d{4}
                    |
                    (?<!\d)\d{2}[\s\-.]\d{4}[\s\-.]\d{4}(?!\d)
                    |
                    (?<!\d)\d{3}[\s\-.]\d{3}[\s\-.]\d{4}(?!\d)
                    |
                    (?<!\d)\d{10}(?!\d)
                )
                """#,
                [.caseInsensitive, .allowCommentsAndWhitespace]
            ),
            (
                .address,
                #"(?:Calle|Avenida|Av\.|Boulevard|Blvd\.|Paseo|Calzada|Privada)\s+[\s\S]{8,240}?(?:C\.?\s*P\.?|C[oó]digo\s+Postal)\s*\d{5}"#,
                [.caseInsensitive]
            ),
            (
                .organization,
                #"\b(?:(?!Apoderado|Legal|Licenciado|Lic|Notario|Demandado|Actor)[A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9.&'’\-]+)(?:(?:\s+(?:de|del|la|las|los|y|e|en|De|Del|La|Las|Los|Y|E|En|DE|DEL|LA|LAS|LOS|Y|EN))?\s+(?!Apoderado|Legal|Licenciado|Notario)[A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9.&'’\-]+){1,6},?\s*(?i:S\.?\s*A\.?(?:\s*P\.?\s*I\.?)?\s*(?:de\s+)?C\.?\s*V\.|S\.?\s*de\s+R\.?\s*L\.?(?:\s*(?:de\s+)?C\.?\s*V\.?)?)"#,
                []
            ),
            (
                .organization,
                #"\bbanco\s+([A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9.&'’\-]+(?:\s+[A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9.&'’\-]+){0,3})"#,
                [.caseInsensitive]
            ),
            (
                .organization,
                #"\bmarca\s+([A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑ0-9\-]+)"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"\bmodelo\s+([A-Z0-9][A-Za-z0-9\-]+)"#,
                [.caseInsensitive]
            ),
            (
                .identifier,
                #"Notario\s+P[uú]blico\s+No\.?\s*\d+"#,
                [.caseInsensitive]
            ),
            (
                .organization,
                #"Instituto Nacional Electoral(?:\s*\(\s*INE\s*\))?"#,
                [.caseInsensitive]
            ),
            (
                .name,
                #"(?:ACTOR|DEMANDADO|QUEJOSO|IMPUTADO|OFENDIDO|TERCERO\s+INTERESADO)\s*:\s*([A-ZÁÉÍÓÚÜÑ]+(?:[ \t]+[A-ZÁÉÍÓÚÜÑ]+){1,8})"#,
                []
            ),
            (
                .name,
                #"\b(?:[Ll]ic(?:enciado|enciada)?|[Dd]ra?|[Mm]tro)\.?\s+([A-ZÁÉÍÓÚÜÑ][a-záéíóúüñ]+(?:\s+(?!Apoderado|Legal|Notario)[A-ZÁÉÍÓÚÜÑ][a-záéíóúüñ]+){1,3})"#,
                []
            ),
            (
                .name,
                #"\b(?:el|la|al|El|La|Al)\s+C\.\s+(?!Juez|Jueza|JUEZ|JUEZA|Magistrado|Magistrada)([A-ZÁÉÍÓÚÜÑ][a-záéíóúüñ]+(?:\s+[A-ZÁÉÍÓÚÜÑ][a-záéíóúüñ]+){1,5})"#,
                []
            )
        ]

        return specs.map { type, pattern, options in
            let regex = try! NSRegularExpression(pattern: pattern, options: options)
            return (type, regex)
        }
    }

    private static func preferredRange(in result: NSTextCheckingResult) -> NSRange {
        if result.numberOfRanges > 1 {
            let inner = result.range(at: 1)
            if inner.location != NSNotFound, inner.length > 0 {
                return inner
            }
        }
        return result.range
    }

    private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }
}
