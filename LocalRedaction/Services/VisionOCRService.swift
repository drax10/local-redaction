import CoreGraphics
import Foundation
import PDFKit
import Vision

enum VisionOCRService {
    private static let maxLongestEdge: CGFloat = 2200
    private static let renderScale: CGFloat = 3

    static func recognizeText(in page: PDFPage) throws -> String {
        try Task.checkCancellation()
        guard let image = rasterize(page) else {
            return ""
        }
        return try recognizeText(in: image)
    }

    static func recognizeText(in image: CGImage) throws -> String {
        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages()
        request.customWords = ["RFC", "CURP", "CLABE", "SAT", "IMSS", "ISSSTE", "INE"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations
            .sorted(by: readingOrder)
            .compactMap { $0.topCandidates(1).first?.string }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rasterize(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let longest = max(bounds.width, bounds.height)
        let scale = min(renderScale, maxLongestEdge / longest)
        var size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if page.rotation == 90 || page.rotation == 270 {
            size = CGSize(width: size.height, height: size.width)
        }
        size.width = max(size.width.rounded(), 1)
        size.height = max(size.height.rounded(), 1)

        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func recognitionLanguages() -> [String] {
        let preferred = ["es-MX", "es-ES", "en-US"]
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        let supported = (try? probe.supportedRecognitionLanguages()) ?? []

        let matched = preferred.filter { code in
            supported.contains(code)
                || supported.contains(where: { $0.hasPrefix(String(code.prefix(2))) })
        }
        return matched.isEmpty ? Array(supported.prefix(3)) : matched
    }

    /// Vision boxes origin is bottom-left; sort top-to-bottom, then left-to-right.
    private static func readingOrder(_ lhs: VNRecognizedTextObservation, _ rhs: VNRecognizedTextObservation) -> Bool {
        let left = lhs.boundingBox
        let right = rhs.boundingBox
        if abs(left.maxY - right.maxY) > 0.02 {
            return left.maxY > right.maxY
        }
        return left.minX < right.minX
    }
}
