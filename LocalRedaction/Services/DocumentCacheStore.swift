import Foundation

actor DocumentCacheStore {
    static let shared = DocumentCacheStore()

    private let rootURL: URL
    private let documentsURL: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil) {
        let root: URL
        if let rootURL {
            root = rootURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            root = support.appendingPathComponent("RedaccionLocal", isDirectory: true)
        }
        self.rootURL = root
        documentsURL = root.appendingPathComponent("Documents", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadSummaries() -> [CachedDocumentSummary] {
        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        if let summaries = readIndex() {
            return summaries.sorted { $0.updatedAt > $1.updatedAt }
        }
        return rebuildIndex().sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadRecord(id: UUID) -> CachedDocumentRecord? {
        let url = documentURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedDocumentRecord.self, from: data)
    }

    func save(_ record: CachedDocumentRecord) throws {
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        let data = try encoder.encode(record)
        try writeAtomically(data, to: documentURL(for: record.summary.id))

        var summaries = readIndex() ?? []
        if let index = summaries.firstIndex(where: { $0.id == record.summary.id }) {
            summaries[index] = record.summary
        } else {
            summaries.append(record.summary)
        }
        try writeIndex(summaries)
    }

    func delete(id: UUID) throws {
        let url = documentURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var summaries = readIndex() ?? []
        summaries.removeAll { $0.id == id }
        try writeIndex(summaries)
    }

    private func documentURL(for id: UUID) -> URL {
        documentsURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func readIndex() -> [CachedDocumentSummary]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? decoder.decode([CachedDocumentSummary].self, from: data)
    }

    private func writeIndex(_ summaries: [CachedDocumentSummary]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try encoder.encode(summaries)
        try writeAtomically(data, to: indexURL)
    }

    private func rebuildIndex() -> [CachedDocumentSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: nil
        )) ?? []
        var summaries: [CachedDocumentSummary] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(CachedDocumentRecord.self, from: data) else {
                continue
            }
            summaries.append(record.summary)
        }
        if let encoded = try? encoder.encode(summaries) {
            try? writeAtomically(encoded, to: indexURL)
        }
        return summaries
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
