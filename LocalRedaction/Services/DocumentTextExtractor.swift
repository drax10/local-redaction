import Foundation
import PDFKit

enum DocumentExtractionError: LocalizedError {
    case unsupportedFileType(String)
    case unreadablePDF
    case emptyDocument
    case readFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "No se admiten los archivos «\(ext)». Elige un PDF o un archivo .txt."
        case .unreadablePDF:
            return "Este PDF no contiene texto extraíble. Los PDF escaneados (solo imagen) no se admiten en esta versión."
        case .emptyDocument:
            return "El documento parece estar vacío."
        case .readFailed:
            return "No se pudo leer el archivo. Puede estar dañado o usar una codificación no compatible."
        }
    }
}

enum DocumentTextExtractor {
    static let allowedExtensions: Set<String> = ["pdf", "txt", "text"]

    static func isSupported(url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    static func extract(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
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
                text = try extractPDF(at: url)
            case "txt", "text":
                text = try readPlainText(at: url)
            default:
                throw DocumentExtractionError.unsupportedFileType(ext.isEmpty ? "desconocido" : ext)
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DocumentExtractionError.emptyDocument
            }
            return text
        }.value
    }

    private static func extractPDF(at url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentExtractionError.unreadablePDF
        }

        var pages: [String] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let pageText = page.string else {
                continue
            }
            pages.append(pageText)
        }

        let combined = pages.joined(separator: "\n")
            .replacingOccurrences(of: "\u{0c}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw DocumentExtractionError.unreadablePDF
        }
        return combined
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
