import AppKit
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var state: AppState = .upload
    @Published var candidates: [RedactionCandidate] = [] {
        didSet {
            didCopy = false
            if !persistSuppressed {
                refreshRedactionOutput()
                schedulePersist()
            }
        }
    }
    @Published var originalText = ""
    @Published private(set) var redactedPreview = ""
    @Published private(set) var tagsByID: [UUID: String] = [:]
    @Published var processingStatus = "Preparando…"
    @Published var processingProgress: Double = 0
    @Published var sourceFileName = ""
    @Published var errorMessage: String?
    @Published var didCopy = false
    @Published var isImporterPresented = false
    @Published var selectedPreviewText = ""
    @Published var focusedCandidateID: RedactionCandidate.ID?
    @Published var highlightPulse = 0
    @Published var cachedDocuments: [CachedDocumentSummary] = []
    @Published var selectedDocumentID: CachedDocumentSummary.ID?
    @Published var sidebarSearch = ""
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var inFlightID: UUID?
    @Published var inFlightFileName = ""
    @Published var duplicatePrompt: DuplicateScanPrompt?

    var selectedCount: Int {
        candidates.filter(\.isSelected).count
    }

    var navigationTitle: String {
        switch state {
        case .upload: "Redacción Local"
        case .processing: "Analizando"
        case .reviewing, .completed:
            sourceFileName.isEmpty ? "Revisión" : sourceFileName
        }
    }

    var canOpenDocument: Bool {
        true
    }

    var canStartOver: Bool {
        state == .reviewing || state == .completed || state == .processing || inFlightID != nil
    }

    var canRedactSelection: Bool {
        let snippet = selectedPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return RedactionSelection.isRedactable(snippet)
            && !TextSpanLocator.nsRanges(of: snippet, in: originalText).isEmpty
    }

    var canCopyRedactedText: Bool {
        (state == .reviewing || state == .completed) && !originalText.isEmpty
    }

    var filteredDocuments: [CachedDocumentSummary] {
        sidebarDocuments.filter { $0.matches(sidebarSearch) }
    }

    var sidebarDocuments: [CachedDocumentSummary] {
        var items = cachedDocuments
        if let inFlightID, !items.contains(where: { $0.id == inFlightID }) {
            items.insert(inFlightPlaceholder(id: inFlightID), at: 0)
        }
        return items
    }

    func isProcessingDocument(_ id: UUID) -> Bool {
        inFlightID == id
    }

    /// Text to find in the redacted preview for the focused table row.
    var focusedPreviewNeedle: String {
        guard let id = focusedCandidateID,
              let candidate = candidates.first(where: { $0.id == id }) else {
            return ""
        }
        return candidate.isSelected ? (tagsByID[candidate.id] ?? tag(for: candidate)) : candidate.originalText
    }

    func pulsePreviewHighlight() {
        highlightPulse += 1
    }

    private let extractionService = PIIExtractionService()
    private let cacheStore = DocumentCacheStore.shared
    private var processingTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var persistSuppressed = false
    private var currentFileHash = ""
    private var redactionIndex = RedactionIndex()

    init() {
        ScanNotificationService.shared.onOpenDocument = { [weak self] id in
            self?.selectCachedDocument(id: id)
        }
        Task { await loadCachedDocuments() }
    }

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
        duplicatePrompt = nil
        processingTask?.cancel()
        ScanNotificationService.shared.requestAccessIfNeeded()
        processingTask = Task { await processFile(at: url, replacingID: nil) }
    }

    func openExistingInsteadOfRescan() {
        guard let prompt = duplicatePrompt else { return }
        duplicatePrompt = nil
        processingTask = Task { await openCachedDocument(id: prompt.existing.id) }
    }

    func rescanExistingDocument() {
        guard let prompt = duplicatePrompt else { return }
        duplicatePrompt = nil
        processingTask?.cancel()
        ScanNotificationService.shared.requestAccessIfNeeded()
        processingTask = Task { await processFile(at: prompt.url, replacingID: prompt.existing.id) }
    }

    func dismissDuplicatePrompt() {
        duplicatePrompt = nil
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }

    func showDropZone() {
        selectedDocumentID = nil
        persistSuppressed = true
        state = .upload
        candidates = []
        originalText = ""
        redactedPreview = ""
        tagsByID = [:]
        redactionIndex = RedactionIndex()
        sourceFileName = inFlightFileName
        didCopy = false
        errorMessage = nil
        selectedPreviewText = ""
        focusedCandidateID = nil
        highlightPulse = 0
        persistSuppressed = false
        if inFlightID == nil {
            processingStatus = "Preparando…"
            processingProgress = 0
            sourceFileName = ""
            currentFileHash = ""
        }
    }

    func processFile(at url: URL, replacingID: UUID?) async {
        let jobID = replacingID ?? UUID()
        beginInFlight(id: jobID, fileName: url.lastPathComponent)

        processingStatus = "Comprobando el archivo…"
        do {
            let hash = try await DocumentTextExtractor.fileFingerprint(from: url)
            try Task.checkCancellation()
            currentFileHash = hash

            if replacingID == nil, let existing = cachedDocuments.first(where: { $0.fileHash == hash }) {
                guard inFlightID == jobID else { return }
                let wasWatching = selectedDocumentID == jobID
                clearInFlight()
                duplicatePrompt = DuplicateScanPrompt(url: url, existing: existing)
                if wasWatching {
                    showDropZone()
                }
                return
            }

            let fileName = url.lastPathComponent
            let text = try await DocumentTextExtractor.extract(from: url) { progress, status in
                await self.applyProgress(progress, status: status, jobID: jobID)
            }
            try Task.checkCancellation()
            guard inFlightID == jobID else { return }

            let extracted = try await extractionService.extract(from: text) { progress, status in
                await self.applyProgress(progress, status: status, jobID: jobID)
            }
            try Task.checkCancellation()
            guard inFlightID == jobID else { return }

            await saveFinishedDocument(
                id: jobID,
                fileName: fileName,
                hash: hash,
                text: text,
                candidates: extracted
            )

            guard inFlightID == jobID else { return }
            let stillSelected = selectedDocumentID == jobID
            clearInFlight()

            if stillSelected {
                persistSuppressed = true
                sourceFileName = fileName
                originalText = text
                currentFileHash = hash
                candidates = extracted
                focusedCandidateID = nil
                selectedPreviewText = ""
                persistSuppressed = false
                refreshRedactionOutput()
                selectedDocumentID = jobID
                state = .reviewing
            }

            ScanNotificationService.shared.notifyScanFinished(
                id: jobID,
                fileName: fileName,
                findingCount: extracted.count,
                userIsWatching: stillSelected
            )
        } catch is CancellationError {
            guard inFlightID == jobID else { return }
            let wasWatching = selectedDocumentID == jobID
            clearInFlight()
            if wasWatching {
                showDropZone()
            }
        } catch {
            guard inFlightID == jobID else { return }
            let wasWatching = selectedDocumentID == jobID
            clearInFlight()
            if wasWatching {
                errorMessage = error.localizedDescription
                showDropZone()
            }
        }
    }

    func openCachedDocument(id: UUID) async {
        guard let record = await cacheStore.loadRecord(id: id) else { return }
        persistTask?.cancel()
        persistSuppressed = true
        selectedDocumentID = record.summary.id
        sourceFileName = record.summary.fileName
        originalText = record.originalText
        currentFileHash = record.summary.fileHash
        candidates = record.candidates
        focusedCandidateID = nil
        selectedPreviewText = ""
        didCopy = false
        errorMessage = nil
        persistSuppressed = false
        refreshRedactionOutput()
        state = .reviewing
    }

    func selectCachedDocument(id: UUID?) {
        guard let id else { return }
        if id == inFlightID {
            selectedDocumentID = id
            sourceFileName = inFlightFileName
            state = .processing
            return
        }
        guard id != selectedDocumentID || state != .reviewing else { return }
        Task { await openCachedDocument(id: id) }
    }

    func deleteCachedDocument(id: UUID) {
        if id == inFlightID {
            cancelProcessing()
            return
        }
        Task {
            persistTask?.cancel()
            try? await cacheStore.delete(id: id)
            cachedDocuments.removeAll { $0.id == id }
            if selectedDocumentID == id {
                showDropZone()
            }
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
        tagsByID[candidate.id] ?? "[\(candidate.type.tagLabel) -]"
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(redactedPreview, forType: .string)
        didCopy = true
    }

    func startOver() {
        showDropZone()
    }

    func selectAll(_ selected: Bool) {
        candidates = candidates.map { candidate in
            var updated = candidate
            updated.isSelected = selected
            return updated
        }
    }

    private func applyProgress(_ progress: Double, status: String, jobID: UUID? = nil) {
        if let jobID, inFlightID != jobID { return }
        processingProgress = progress
        processingStatus = status
    }

    private func refreshRedactionOutput() {
        let token = "\(selectedDocumentID?.uuidString ?? sourceFileName)|\((originalText as NSString).length)"
        redactionIndex.synchronize(token: token, text: originalText, candidates: candidates)
        tagsByID = RedactionEngine.numberedTags(for: candidates)
        redactedPreview = redactionIndex.apply(
            text: originalText,
            tags: tagsByID,
            selectedIDs: Set(candidates.filter(\.isSelected).map(\.id))
        )
    }

    private func loadCachedDocuments() async {
        cachedDocuments = await cacheStore.loadSummaries()
    }

    private func schedulePersist() {
        guard !persistSuppressed, selectedDocumentID != nil, state == .reviewing || state == .completed else {
            return
        }
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistCurrentDocument(immediate: true)
        }
    }

    private func beginInFlight(id: UUID, fileName: String) {
        inFlightID = id
        inFlightFileName = fileName
        selectedDocumentID = id
        sourceFileName = fileName
        processingProgress = 0.04
        processingStatus = "Leyendo el documento…"
        state = .processing
        didCopy = false
        errorMessage = nil
        focusedCandidateID = nil
        selectedPreviewText = ""
        persistSuppressed = true
        candidates = []
        originalText = ""
        redactedPreview = ""
        tagsByID = [:]
        redactionIndex = RedactionIndex()
        persistSuppressed = false
    }

    private func clearInFlight() {
        inFlightID = nil
        inFlightFileName = ""
    }

    private func inFlightPlaceholder(id: UUID) -> CachedDocumentSummary {
        CachedDocumentSummary(
            id: id,
            fileName: inFlightFileName,
            fileHash: currentFileHash,
            processedAt: Date(),
            updatedAt: Date(),
            candidateCount: 0,
            searchPreview: inFlightFileName.lowercased()
        )
    }

    private func saveFinishedDocument(
        id: UUID,
        fileName: String,
        hash: String,
        text: String,
        candidates: [RedactionCandidate]
    ) async {
        let now = Date()
        let existing = cachedDocuments.first(where: { $0.id == id })
        let summary = CachedDocumentSummary(
            id: id,
            fileName: fileName,
            fileHash: hash,
            processedAt: existing?.processedAt ?? now,
            updatedAt: now,
            candidateCount: candidates.count,
            searchPreview: Self.searchPreview(fileName: fileName, text: text)
        )
        let record = CachedDocumentRecord(
            summary: summary,
            originalText: text,
            candidates: candidates
        )
        do {
            try await cacheStore.save(record)
            if let index = cachedDocuments.firstIndex(where: { $0.id == id }) {
                cachedDocuments[index] = summary
            } else {
                cachedDocuments.insert(summary, at: 0)
            }
            cachedDocuments.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            if selectedDocumentID == id {
                errorMessage = "No se pudo guardar el documento en el historial."
            }
        }
    }

    private func persistCurrentDocument(immediate: Bool) async {
        guard !originalText.isEmpty, !sourceFileName.isEmpty else { return }
        guard let id = selectedDocumentID ?? inFlightID else { return }
        await saveFinishedDocument(
            id: id,
            fileName: sourceFileName,
            hash: currentFileHash,
            text: originalText,
            candidates: candidates
        )
        if selectedDocumentID == nil {
            selectedDocumentID = id
        }
    }

    private static func searchPreview(fileName: String, text: String) -> String {
        fileName.lowercased() + "\n" + text.prefix(2_000).lowercased()
    }
}

#if DEBUG
extension AppViewModel {
    static func preview(state: AppState) -> AppViewModel {
        let viewModel = AppViewModel()
        viewModel.persistSuppressed = true
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
        let summary = CachedDocumentSummary(
            id: UUID(),
            fileName: "contrato-ejemplo.txt",
            fileHash: "preview",
            processedAt: Date(),
            updatedAt: Date(),
            candidateCount: viewModel.candidates.count,
            searchPreview: "contrato-ejemplo.txt"
        )
        viewModel.cachedDocuments = [summary]
        viewModel.selectedDocumentID = summary.id
        if state == .processing {
            viewModel.inFlightID = summary.id
            viewModel.inFlightFileName = summary.fileName
        }
        viewModel.persistSuppressed = false
        viewModel.refreshRedactionOutput()
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
