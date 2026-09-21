import Foundation

/// Orchestrates the two-layer extraction pipeline on a background executor.
final class PIIExtractionService: Sendable {
    func extract(
        from text: String,
        progress: @escaping @Sendable (Double, String) async -> Void
    ) async throws -> [RedactionCandidate] {
        try Task.checkCancellation()
        await progress(0.18, "Buscando identificadores, empresas y cédulas…")

        let regexMatches = await Task.detached(priority: .userInitiated) {
            RegexExtractionService().extract(from: text)
        }.value

        try Task.checkCancellation()
        let usingLLM = NLPExtractionService.isLanguageModelAvailable
        await progress(
            0.45,
            usingLLM
                ? "Analizando nombres, empresas y domicilios con Apple Intelligence…"
                : "Analizando nombres, empresas y domicilios…"
        )

        let nlpMatches = await NLPExtractionService().extract(from: text) { current, total in
            let fraction = Double(current) / Double(max(total, 1))
            await progress(
                0.45 + 0.40 * fraction,
                "Analizando fragmento \(current)/\(total)…"
            )
        }

        try Task.checkCancellation()
        await progress(0.88, "Preparando los resultados…")

        let merged = Self.merge(regex: regexMatches, nlp: nlpMatches)
        let candidates = Self.makeCandidates(from: merged)

        await progress(1.0, "Análisis concluido")
        return candidates
    }

    private static func merge(regex: [ExtractedMatch], nlp: [ExtractedMatch]) -> [ExtractedMatch] {
        var accepted = regex
        for match in nlp {
            if let index = accepted.firstIndex(where: {
                NSIntersectionRange($0.nsRange, match.nsRange).length > 0
            }) {
                let existing = accepted[index]
                if shouldReplace(existing, with: match) {
                    accepted[index] = match
                }
                continue
            }
            accepted.append(match)
        }
        return accepted.sorted { $0.nsRange.location < $1.nsRange.location }
    }

    /// Keep a longer contextual span (name, company, address) over a shorter
    /// regex hit of the same kind. Structured IDs always win over a surrounding
    /// misclassified phrase (e.g. INE credential tagged as cédula).
    private static func shouldReplace(_ existing: ExtractedMatch, with incoming: ExtractedMatch) -> Bool {
        let contextual: Set<PIIType> = [.name, .organization, .address]
        guard contextual.contains(existing.type), contextual.contains(incoming.type) else {
            return false
        }
        return incoming.nsRange.length > existing.nsRange.length
    }

    /// Unique `(type, text)` pairs share a single replacement tag. Duplicate
    /// occurrences in the document are still all replaced by that tag.
    private static func makeCandidates(from matches: [ExtractedMatch]) -> [RedactionCandidate] {
        var seen = Set<String>()
        var candidates: [RedactionCandidate] = []

        for match in matches {
            let exact = match.text
            let normalized = TextSpanLocator.normalized(exact)
            guard normalized.count >= 2 else { continue }
            guard PIICandidateFilter.shouldKeep(exact, as: match.type) else { continue }

            let key = "\(match.type.rawValue)|\(normalized)"
            guard seen.insert(key).inserted else { continue }

            candidates.append(
                RedactionCandidate(
                    originalText: exact,
                    type: match.type
                )
            )
        }

        return candidates
    }
}
