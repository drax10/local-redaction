import AppKit
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var state: AppState = .upload
    @Published var candidates: [RedactionCandidate] = [] {
        didSet { didCopy = false }
    }
    @Published var originalText = ""
    @Published var processingStatus = "Preparando…"
    @Published var processingProgress: Double = 0
    @Published var sourceFileName = ""
    @Published var errorMessage: String?
    @Published var didCopy = false
    @Published var isImporterPresented = false
    @Published var selectedPreviewText = ""
    @Published var focusedCandidateID: RedactionCandidate.ID?
    @Published var highlightPulse = 0

    var selectedCount: Int {
        candidates.filter(\.isSelected).count
    }

    var redactedPreview: String {
        RedactionEngine.redact(text: originalText, candidates: candidates)
    }

    var navigationTitle: String {
        switch state {
        case .upload: "Redacción Local"
        case .processing: "Analizando"
        case .reviewing: "Revisión"
        case .completed: "Revisión"
        }
    }

    var canOpenDocument: Bool {
        state != .processing
    }

    var canStartOver: Bool {
        state == .reviewing || state == .completed || state == .processing
    }

    var canRedactSelection: Bool {
        let snippet = selectedPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return RedactionSelection.isRedactable(snippet)
            && !TextSpanLocator.nsRanges(of: snippet, in: originalText).isEmpty
    }

    var canCopyRedactedText: Bool {
        (state == .reviewing || state == .completed) && !originalText.isEmpty
    }

    /// Text to find in the redacted preview for the focused table row.
    var focusedPreviewNeedle: String {
        guard let id = focusedCandidateID,
              let candidate = candidates.first(where: { $0.id == id }) else {
            return ""
        }
        return candidate.isSelected ? tag(for: candidate) : candidate.originalText
    }

    func pulsePreviewHighlight() {
        highlightPulse += 1
    }

    private let extractionService = PIIExtractionService()
    private var processingTask: Task<Void, Never>?

    func presentOpenPanel() {
        isImporterPresented = true
    }

    func process(url: URL) {
        guard DocumentTextExtractor.isSupported(url: url) else {
            errorMessage = DocumentExtractionError.unsupportedFileType(
                url.pathExtension.isEmpty ? "desconocido" : url.pathExtension
            ).localizedDescription
            return
        }
        processingTask?.cancel()
        processingTask = Task { await processFile(at: url) }
    }

    func processFile(at url: URL) async {
        didCopy = false
        errorMessage = nil
        sourceFileName = url.lastPathComponent
        processingProgress = 0.05
        processingStatus = "Leyendo el documento…"
        state = .processing

        do {
            let text = try await DocumentTextExtractor.extract(from: url)
            originalText = text

            let extracted = try await extractionService.extract(from: text) { progress, status in
                await self.applyProgress(progress, status: status)
            }

            candidates = extracted
            focusedCandidateID = nil
            state = .reviewing
        } catch is CancellationError {
            if state == .processing {
                startOver()
            }
        } catch {
            errorMessage = error.localizedDescription
            state = .upload
        }
    }

    func addRedaction(fromSelectedText snippet: String) {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RedactionSelection.isRedactable(trimmed) else { return }
        guard let firstRange = TextSpanLocator.nsRanges(of: trimmed, in: originalText).first,
              let stringRange = Range(firstRange, in: originalText) else { return }

        selectedPreviewText = ""

        let exact = String(originalText[stringRange])
        let normalized = TextSpanLocator.normalized(exact)

        if let existingIndex = candidates.firstIndex(where: {
            TextSpanLocator.normalized($0.originalText) == normalized
        }) {
            candidates[existingIndex].isSelected = true
            return
        }

        let guessedType = ClassificationService.classifyDeterministic(trimmed)
        let candidate = RedactionCandidate(originalText: exact, type: guessedType)
        candidates.insert(candidate, at: insertionIndex(for: exact))

        Task {
            let refined = await ClassificationService.classify(trimmed)
            guard let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
            if candidates[index].type == guessedType {
                candidates[index].type = refined
            }
        }
    }

    func redactSelectedText() {
        addRedaction(fromSelectedText: selectedPreviewText)
    }

    private func insertionIndex(for snippet: String) -> Int {
        guard let snippetRange = TextSpanLocator.nsRanges(of: snippet, in: originalText).first else {
            return candidates.count
        }

        for (index, candidate) in candidates.enumerated() {
            if let candidateRange = TextSpanLocator.nsRanges(of: candidate.originalText, in: originalText).first,
               candidateRange.location > snippetRange.location {
                return index
            }
        }
        return candidates.count
    }

    func tag(for candidate: RedactionCandidate) -> String {
        RedactionEngine.numberedTags(for: candidates)[candidate.id]
            ?? "[\(candidate.type.tagLabel) -]"
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(redactedPreview, forType: .string)
        didCopy = true
    }

    func startOver() {
        processingTask?.cancel()
        processingTask = nil
        state = .upload
        candidates = []
        originalText = ""
        processingStatus = "Preparando…"
        processingProgress = 0
        sourceFileName = ""
        didCopy = false
        errorMessage = nil
        selectedPreviewText = ""
        focusedCandidateID = nil
        highlightPulse = 0
    }

    func selectAll(_ selected: Bool) {
        candidates = candidates.map { candidate in
            var updated = candidate
            updated.isSelected = selected
            return updated
        }
    }

    private func applyProgress(_ progress: Double, status: String) {
        processingProgress = progress
        processingStatus = status
    }
}

#if DEBUG
extension AppViewModel {
    static func preview(state: AppState) -> AppViewModel {
        let viewModel = AppViewModel()
        viewModel.state = state
        viewModel.sourceFileName = "contrato-ejemplo.txt"
        viewModel.originalText = SampleDocument.contrato
        viewModel.processingStatus = "Analizando nombres y domicilios…"
        viewModel.processingProgress = 0.62
        viewModel.candidates = [
            RedactionCandidate(originalText: "Juan Carlos Hernández López", type: .name),
            RedactionCandidate(originalText: "HEHL850315AB1", type: .rfc),
            RedactionCandidate(originalText: "HELJ850315HDFRRN09", type: .curp),
            RedactionCandidate(originalText: "Calle Morelos 123", type: .address),
            RedactionCandidate(originalText: "+52 55 1234 5678", type: .phone),
            RedactionCandidate(originalText: "juan.hernandez@correo.com", type: .email),
            RedactionCandidate(originalText: "012180001234567897", type: .clabe)
        ]
        return viewModel
    }
}

enum SampleDocument {
    static let contrato = """
    CONTRATO DE PRESTACIÓN DE SERVICIOS PROFESIONALES

    En la Ciudad de México, a 18 de septiembre de 2026, comparecen:

    Por una parte, el C. Juan Carlos Hernández López, por su propio derecho, con RFC HEHL850315AB1 y CURP HELJ850315HDFRRN09, con domicilio en Calle Morelos 123, Colonia Centro, Ciudad de México, C.P. 06000.

    Teléfono: +52 55 1234 5678
    Correo electrónico: juan.hernandez@correo.com
    CLABE interbancaria: 012180001234567897
    """
}
#endif
