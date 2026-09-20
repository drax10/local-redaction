import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Classifies a user-selected snippet into a PII category.
/// Uses on-device Foundation Models when Apple Intelligence is available,
/// then regex, then NLTagger heuristics.
enum ClassificationService {
    static func classifyDeterministic(_ text: String) -> PIIType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .name }

        let regexMatches = RegexExtractionService().extract(from: trimmed)
        if let match = regexMatches.max(by: { $0.text.count < $1.text.count }) {
            let ratio = Double(match.text.count) / Double(max(trimmed.count, 1))
            if ratio >= 0.65 {
                return match.type
            }
        }

        let lowered = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
        let addressHints = [
            "calle", "avenida", "av.", "boulevard", "blvd", "col.", "colonia",
            "c.p.", "cp.", "codigo postal", "alcaldia", "delegacion", "piso",
            "depto", "departamento", "ciudad de", "fraccionamiento", "mz.", "lote"
        ]
        if addressHints.contains(where: { lowered.contains($0) }) {
            return .address
        }

        if lowered.contains("cedula profesional") {
            return .cedula
        }

        let organizationHints = [
            "s.a. de c.v", "s. de r.l", "persona moral", "razon social",
            "s.a.p.i", "s.a.b. de c.v"
        ]
        if organizationHints.contains(where: { lowered.contains($0) }) {
            return .organization
        }

        let identifierHints = [
            "nss", "seguro social", "pasaporte", "matricula", "folio",
            "licencia", "numero de empleado", "identificacion", "credencial",
            "clave de elector", "ine", "cic", "placas", "vin", "tarjeta",
            "nacido", "nacida", "expediente", "escritura publica"
        ]
        if identifierHints.contains(where: { lowered.contains($0) }) {
            return .identifier
        }

        let nlpMatches = NLPExtractionService().extractWithNLTagger(from: trimmed)
        if nlpMatches.contains(where: { $0.type == .address }) {
            return .address
        }
        if nlpMatches.contains(where: { $0.type == .organization }) {
            return .organization
        }
        if nlpMatches.contains(where: { $0.type == .name }) {
            return .name
        }

        return .name
    }

    static func classify(_ text: String) async -> PIIType {
        if let llmType = await classifyWithLanguageModel(text) {
            return llmType
        }
        return classifyDeterministic(text)
    }

    private static func classifyWithLanguageModel(_ text: String) async -> PIIType? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelClassifier.classify(text)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
enum LLMCategory {
    case rfc
    case curp
    case clabe
    case cedula
    case telefono
    case correo
    case nombre
    case empresa
    case domicilio
    case identificador

    var piiType: PIIType {
        switch self {
        case .rfc: .rfc
        case .curp: .curp
        case .clabe: .clabe
        case .cedula: .cedula
        case .telefono: .phone
        case .correo: .email
        case .nombre: .name
        case .empresa: .organization
        case .domicilio: .address
        case .identificador: .identifier
        }
    }
}

@available(macOS 26.0, *)
enum FoundationModelClassifier {
    static func classify(_ text: String) async -> PIIType? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(
            instructions: """
            Clasificas datos personales en documentos jurídicos mexicanos.
            Elige una sola categoría para el fragmento.
            RFC: clave del Registro Federal de Contribuyentes.
            CURP: Clave Única de Registro de Población.
            CLABE: cuenta interbancaria de 18 dígitos.
            cedula: SOLO cédula profesional. NUNCA credencial para votar, INE, clave de elector ni cédula de identificación fiscal.
            telefono: número telefónico mexicano.
            correo: dirección de correo electrónico.
            nombre: nombre de una persona física.
            empresa: organización: persona moral, banco, marca, notaría, institución.
            domicilio: dirección, colonia, alcaldía, ciudad o lugar.
            identificador: cualquier otro dato identificable: INE, clave de elector, CIC, pasaporte, placas, VIN, tarjeta, fecha de nacimiento, expediente, escritura, modelo.
            No inventes otra categoría.
            """
        )

        do {
            let response = try await session.respond(
                to: "Clasifica este fragmento:\n\(text)",
                generating: LLMCategory.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 32
                )
            )
            return response.content.piiType
        } catch {
            return nil
        }
    }
}
#endif
