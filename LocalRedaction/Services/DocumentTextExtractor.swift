import AppKit
import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum DocumentExtractionError: LocalizedError {
    case unsupportedFileType(String)
    case unreadablePDF
    case unreadableWord
    case emptyDocument
    case readFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "No se admiten los archivos «\(ext)». Elige un PDF, Word (.doc o .docx) o un archivo .txt."
        case .unreadablePDF:
            return "No se pudo leer el texto de este PDF, ni siquiera con OCR en este Mac. Prueba con un escaneo más nítido."
        case .unreadableWord:
            return "No se pudo extraer el texto de este documento de Word. Puede estar dañado, protegido con contraseña o ser una versión no compatible."
        case .emptyDocument:
            return "El documento parece estar vacío."
        case .readFailed:
            return "No se pudo leer el archivo. Puede estar dañado o usar una codificación no compatible."
        }
    }
}

enum DocumentTextExtractor {
    static let allowedExtensions: Set<String> = ["pdf", "txt", "text", "doc", "docx"]

    static var allowedContentTypes: [UTType] {
        [.pdf, .plainText, .utf8PlainText, .wordDOCX, .wordDOC]
    }

    static func isSupported(url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    static func fileFingerprint(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
    }

    static func extract(
        from url: URL,
        progress: (@Sendable (Double, String) async -> Void)? = nil
    ) async throws -> String {
        let work = Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let ext = url.pathExtension.lowercased()
            let text: String
            switch ext {
            case "pdf":
                text = try await extractPDF(at: url, progress: progress)
            case "txt", "text":
                text = try readPlainText(at: url)
            case "docx":
                text = try extractDOCX(at: url)
            case "doc":
                text = try extractDOC(at: url)
            default:
                throw DocumentExtractionError.unsupportedFileType(ext.isEmpty ? "desconocido" : ext)
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DocumentExtractionError.emptyDocument
            }
            return text
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// Pages with a real text layer are used as-is. Image-only (scanned) pages
    /// go through on-device Vision OCR so mixed PDFs still work.
    private static func extractPDF(
        at url: URL,
        progress: (@Sendable (Double, String) async -> Void)?
    ) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentExtractionError.unreadablePDF
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw DocumentExtractionError.emptyDocument
        }

        var pages: [String] = []
        pages.reserveCapacity(pageCount)
        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }

            let fraction = Double(index) / Double(pageCount)
            await progress?(0.05 + 0.12 * fraction, "Leyendo la página \(index + 1)/\(pageCount)…")

            if let embedded = usableEmbeddedText(page.string) {
                pages.append(embedded)
                continue
            }

            await progress?(
                0.05 + 0.12 * fraction,
                "Reconociendo texto (OCR) \(index + 1)/\(pageCount)…"
            )
            let ocr = (try? VisionOCRService.recognizeText(in: page)) ?? ""
            if !ocr.isEmpty {
                pages.append(ocr)
            } else if let fallback = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !fallback.isEmpty {
                pages.append(fallback)
            }
        }

        let combined = pages.joined(separator: "\n")
            .replacingOccurrences(of: "\u{0c}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw DocumentExtractionError.unreadablePDF
        }
        return combined
    }

    /// Ignore leftover page numbers or a failed prior OCR layer of a few glyphs.
    private static func usableEmbeddedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .replacingOccurrences(of: "\u{0c}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let alphanumerics = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        guard alphanumerics >= 40 else { return nil }
        return trimmed
    }

    private static func extractDOCX(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = try? WordOOXMLTextExtractor.plainText(from: data) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return text
            }
        }
        return try extractWordWithAppKit(at: url, type: .officeOpenXML)
    }

    private static func extractDOC(at url: URL) throws -> String {
        if let officeOpenXML = try? extractWordWithAppKit(at: url, type: .officeOpenXML),
           !officeOpenXML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return officeOpenXML
        }
        return try extractWordWithAppKit(at: url, type: .docFormat)
    }

    private static func extractWordWithAppKit(
        at url: URL,
        type: NSAttributedString.DocumentType
    ) throws -> String {
        let load: () throws -> String = {
            var attributes: NSDictionary?
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: &attributes
            )
            let text = attributed.string
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentExtractionError.emptyDocument
            }
            return text
        }

        if Thread.isMainThread {
            return try load()
        }

        var result: Result<String, Error>!
        DispatchQueue.main.sync {
            result = Result(catching: load)
        }
        return try result.get()
    }

    private static func readPlainText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // Mexican legal files are occasionally saved as Latin-1 / Windows-1252.
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        if let windows = String(data: data, encoding: .windowsCP1252) {
            return windows
        }
        throw DocumentExtractionError.readFailed
    }
}

extension UTType {
    static let wordDOCX = UTType(filenameExtension: "docx")
        ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    static let wordDOC = UTType(filenameExtension: "doc")
        ?? UTType(importedAs: "com.microsoft.word.doc")
}
