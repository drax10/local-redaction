import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Contextual extractor for names, companies, addresses and other identifiers.
/// Prefers on-device Foundation Models; falls back to NLTagger.
final class NLPExtractionService: Sendable {
    static var isLanguageModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    func extract(
        from text: String,
        onChunk: (@Sendable (Int, Int) async -> Void)? = nil
    ) async -> [ExtractedMatch] {
        if let llmMatches = await extractWithLanguageModel(from: text, onChunk: onChunk) {
            return Self.mergeSupplementalNames(llmMatches, from: text)
        }
        return extractWithNLTagger(from: text)
    }

    private func extractWithLanguageModel(
        from text: String,
        onChunk: (@Sendable (Int, Int) async -> Void)?
    ) async -> [ExtractedMatch]? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await DocumentPIIExtractor.extract(from: text, onChunk: onChunk)
        }
        #endif
        return nil
    }

    func extractWithNLTagger(from text: String) -> [ExtractedMatch] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let fullRange = text.startIndex..<text.endIndex
        tagger.setLanguage(.spanish, range: fullRange)

        var matches: [ExtractedMatch] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: fullRange, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag else { return true }

            let value = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 3 else { return true }

            let type: PIIType?
            switch tag {
            case .personalName:
                type = PersonalNameFilter.shouldKeep(value) ? .name : nil
            case .organizationName:
                type = .organization
            default:
                type = nil
            }

            guard let type else { return true }
            let nsRange = NSRange(tokenRange, in: text)

            matches.append(ExtractedMatch(text: value, type: type, nsRange: nsRange))
            return true
        }

        return matches
    }

    private static func mergeSupplementalNames(
        _ matches: [ExtractedMatch],
        from text: String
    ) -> [ExtractedMatch] {
        let extra = NLPExtractionService().extractWithNLTagger(from: text)
            .filter { $0.type == .name || $0.type == .organization }
        var accepted = matches
        for match in extra {
            let overlaps = accepted.contains {
                NSIntersectionRange($0.nsRange, match.nsRange).length > 0
            }
            if !overlaps {
                accepted.append(match)
            }
        }
        return accepted.sorted { $0.nsRange.location < $1.nsRange.location }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct DocumentPII {
    @Guide(description: "Personas físicas, texto exacto. No cargos como C. Juez.", .maximumCount(24))
    var nombres: [String]

    @Guide(description: "Empresas, bancos, marcas, instituciones. Texto exacto.", .maximumCount(24))
    var empresas: [String]

    @Guide(description: "Domicilios completos, una mención por elemento.", .maximumCount(16))
    var domicilios: [String]

    @Guide(description: "Teléfonos, formato original.", .maximumCount(12))
    var telefonos: [String]

    @Guide(description: "Correos electrónicos.", .maximumCount(12))
    var correos: [String]

    @Guide(description: "Solo cédula profesional, nunca INE ni RFC.", .maximumCount(8))
    var cedulas: [String]

    @Guide(description: "Otros identificadores cortos: pasaporte, placas, VIN, tarjeta, expediente.", .maximumCount(24))
    var otrosIdentificadores: [String]
}

@available(macOS 26.0, *)
enum DocumentPIIExtractor {
    static func extract(
        from text: String,
        onChunk: (@Sendable (Int, Int) async -> Void)? = nil
    ) async -> [ExtractedMatch]? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        var nombres: [String] = []
        var empresas: [String] = []
        var domicilios: [String] = []
        var telefonos: [String] = []
        var correos: [String] = []
        var cedulas: [String] = []
        var otros: [String] = []

        let parts = chunks(from: text)
        var anySuccess = false

        for (index, chunk) in parts.enumerated() {
            if Task.isCancelled { break }
            await onChunk?(index + 1, parts.count)
            if let content = await extractChunk(chunk) {
                nombres.append(contentsOf: content.nombres)
                empresas.append(contentsOf: content.empresas)
                domicilios.append(contentsOf: content.domicilios)
                telefonos.append(contentsOf: content.telefonos)
                correos.append(contentsOf: content.correos)
                cedulas.append(contentsOf: content.cedulas)
                otros.append(contentsOf: content.otrosIdentificadores)
                anySuccess = true
            }
        }

        guard anySuccess else { return nil }

        var matches: [ExtractedMatch] = []
        matches.append(contentsOf: locate(nombres, as: .name, in: text))
        matches.append(contentsOf: locate(empresas, as: .organization, in: text))
        matches.append(contentsOf: locate(domicilios, as: .address, in: text))
        matches.append(contentsOf: locate(telefonos, as: .phone, in: text))
        matches.append(contentsOf: locate(correos, as: .email, in: text))
        matches.append(contentsOf: locate(cedulas, as: .cedula, in: text))
        matches.append(contentsOf: locate(otros, as: .identifier, in: text))
        return dropContainedSpans(matches)
    }

    private static let instructions = """
    Extraes datos identificables de un documento jurídico mexicano para sustituirlos por etiquetas estables.
    Copia SOLO el dato, no la frase jurídica. No extraigas vocabulario procesal genérico.
    Prefiere extraer de más (bancos, marcas, instituciones) antes que dejar un identificador visible.
    nombres: personas físicas. No cargos judiciales (C. Juez, Magistrado).
    empresas: persona moral, banco, marca, institución.
    domicilios: direcciones concretas, no "México" suelto.
    cedulas: solo cédula profesional.
    otrosIdentificadores: pasaporte, placas, VIN, tarjeta, expediente; frase corta.
    No extraigas RFC, CURP ni CLABE. Listas vacías si no hay datos.
    """

    private static func extractChunk(_ chunk: String) async -> DocumentPII? {
        let session = LanguageModelSession(instructions: instructions)
        do {
            return try await withThrowingTaskGroup(of: DocumentPII.self) { group in
                group.addTask {
                    let response = try await session.respond(
                        to: "Extrae los datos identificables de este fragmento:\n\n\(chunk)",
                        generating: DocumentPII.self,
                        options: GenerationOptions(
                            sampling: .greedy,
                            maximumResponseTokens: 1024
                        )
                    )
                    return response.content
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(35))
                    throw ChunkTimeoutError()
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw ChunkTimeoutError()
                }
                return result
            }
        } catch {
            return nil
        }
    }

    private struct ChunkTimeoutError: Error {}

    private static func chunks(from text: String, size: Int = 1800, overlap: Int = 200) -> [String] {
        guard text.count > size else { return [text] }

        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let remaining = text.distance(from: start, to: text.endIndex)
            let length = min(size, remaining)
            var end = text.index(start, offsetBy: length)
            if end < text.endIndex, let newline = text[start..<end].lastIndex(of: "\n"), newline > start {
                end = text.index(after: newline)
            }
            result.append(String(text[start..<end]))
            if end >= text.endIndex { break }
            let back = min(overlap, text.distance(from: start, to: end))
            let next = text.index(end, offsetBy: -back)
            start = next == start ? end : next
        }
        return result
    }

    private static func locate(_ values: [String], as type: PIIType, in text: String) -> [ExtractedMatch] {
        var matches: [ExtractedMatch] = []
        var seen = Set<String>()

        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = TextSpanLocator.normalized(value)
            guard normalized.count >= 3, seen.insert(normalized).inserted else { continue }

            for range in TextSpanLocator.nsRanges(of: value, in: text) {
                guard let stringRange = Range(range, in: text) else { continue }
                let exact = String(text[stringRange])
                if type == .name, !PersonalNameFilter.shouldKeep(exact) {
                    continue
                }
                matches.append(
                    ExtractedMatch(text: exact, type: type, nsRange: range)
                )
            }
        }

        return matches
    }

    private static func dropContainedSpans(_ matches: [ExtractedMatch]) -> [ExtractedMatch] {
        let sorted = matches.sorted { $0.nsRange.length > $1.nsRange.length }
        var kept: [ExtractedMatch] = []
        for match in sorted {
            let contained = kept.contains { existing in
                existing.type == match.type
                    && NSIntersectionRange(existing.nsRange, match.nsRange).length == match.nsRange.length
                    && existing.nsRange.length > match.nsRange.length
            }
            if !contained {
                kept.append(match)
            }
        }
        return kept.sorted { $0.nsRange.location < $1.nsRange.location }
    }
}
#endif

enum PersonalNameFilter {
    static func shouldKeep(_ text: String) -> Bool {
        let normalized = TextSpanLocator.normalized(text)
        guard !normalized.isEmpty else { return false }

        let blocked = [
            "juez", "jueza", "magistrado", "magistrada",
            "secretario", "secretaria", "actuario", "actuaria",
            "c. juez", "c juez", "c. jueza", "c jueza"
        ]
        if blocked.contains(normalized) { return false }

        if normalized.hasPrefix("c. juez")
            || normalized.hasPrefix("c juez")
            || normalized.hasPrefix("juez de")
            || normalized.hasPrefix("jueza de")
            || normalized.hasPrefix("magistrado")
            || normalized.hasPrefix("magistrada") {
            return false
        }

        if normalized.contains("juez de lo") || (normalized.contains("juez") && normalized.contains("en turno")) {
            return false
        }

        return true
    }
}
