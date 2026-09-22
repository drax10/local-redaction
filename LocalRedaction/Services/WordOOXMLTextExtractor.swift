import Foundation
import zlib

/// Pulls visible text from a `.docx` (Office Open XML) package without leaving the device.
enum WordOOXMLTextExtractor {
    static func plainText(from data: Data) throws -> String {
        let zip = try ZipReader(data: data)
        let names = zip.entryNames.filter { name in
            let lower = name.lowercased()
            guard lower.hasPrefix("word/"), lower.hasSuffix(".xml") else { return false }
            let file = lower.dropFirst("word/".count)
            return file == "document.xml"
                || file == "footnotes.xml"
                || file == "endnotes.xml"
                || file.hasPrefix("header")
                || file.hasPrefix("footer")
        }

        guard names.contains(where: { $0.lowercased() == "word/document.xml" }) else {
            throw DocumentExtractionError.unreadableWord
        }

        let ordered = names.sorted { lhs, rhs in
            rank(lhs) < rank(rhs)
        }

        var parts: [String] = []
        parts.reserveCapacity(ordered.count)
        for name in ordered {
            let xml = try zip.data(for: name)
            let text = WordXMLTextParser.plainText(from: xml)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }

        let combined = parts.joined(separator: "\n\n")
        guard !combined.isEmpty else {
            throw DocumentExtractionError.emptyDocument
        }
        return combined
    }

    private static func rank(_ name: String) -> (Int, String) {
        let lower = name.lowercased()
        if lower.hasSuffix("/document.xml") { return (0, lower) }
        if lower.contains("/header") { return (1, lower) }
        if lower.contains("/footer") { return (2, lower) }
        return (3, lower)
    }
}

private enum WordXMLTextParser {
    static func plainText(from xml: Data) -> String {
        let parser = Parser()
        let xmlParser = XMLParser(data: xml)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.result
    }

    private final class Parser: NSObject, XMLParserDelegate {
        private var pieces: [String] = []
        private var capturing = false
        private var buffer = ""

        var result: String {
            pieces.joined()
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch localName(elementName) {
            case "t":
                capturing = true
                buffer = ""
            case "tab":
                pieces.append("\t")
            case "br", "cr":
                pieces.append("\n")
            case "p":
                if !pieces.isEmpty {
                    pieces.append("\n")
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing {
                buffer += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if localName(elementName) == "t" {
                pieces.append(buffer)
                capturing = false
                buffer = ""
            }
        }

        private func localName(_ qualified: String) -> String {
            if let idx = qualified.lastIndex(of: ":") {
                return String(qualified[qualified.index(after: idx)])
            }
            return qualified
        }
    }
}

/// Minimal ZIP reader for OOXML packages (store + deflate, no ZIP64/encryption).
private struct ZipReader {
    let data: Data
    private let entries: [String: Entry]

    var entryNames: [String] { Array(entries.keys) }

    init(data: Data) throws {
        self.data = data
        guard let eocd = Self.findEOCD(in: data) else {
            throw DocumentExtractionError.unreadableWord
        }
        let count = Int(data.u16(eocd + 10))
        let cdOffset = Int(data.u32(eocd + 16))
        guard count > 0, cdOffset > 0, cdOffset < data.count else {
            throw DocumentExtractionError.unreadableWord
        }

        var map: [String: Entry] = [:]
        var cursor = cdOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data.u32(cursor) == 0x02014b50 else {
                throw DocumentExtractionError.unreadableWord
            }
            let method = data.u16(cursor + 10)
            let compressed = Int(data.u32(cursor + 20))
            let uncompressed = Int(data.u32(cursor + 24))
            let nameLen = Int(data.u16(cursor + 28))
            let extraLen = Int(data.u16(cursor + 30))
            let commentLen = Int(data.u16(cursor + 32))
            let localOffset = Int(data.u32(cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else {
                throw DocumentExtractionError.unreadableWord
            }
            if data.u32(cursor + 20) == 0xFFFF_FFFF || data.u32(cursor + 24) == 0xFFFF_FFFF {
                throw DocumentExtractionError.unreadableWord
            }
            let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8)
                ?? String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
            map[name] = Entry(
                method: method,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset
            )
            cursor = nameEnd + extraLen + commentLen
        }
        entries = map
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw DocumentExtractionError.unreadableWord
        }
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, data.u32(local) == 0x04034b50 else {
            throw DocumentExtractionError.unreadableWord
        }
        let nameLen = Int(data.u16(local + 26))
        let extraLen = Int(data.u16(local + 28))
        let dataStart = local + 30 + nameLen + extraLen
        let dataEnd = dataStart + entry.compressedSize
        guard dataEnd <= data.count else {
            throw DocumentExtractionError.unreadableWord
        }
        let payload = data.subdata(in: dataStart..<dataEnd)
        switch entry.method {
        case 0:
            return payload
        case 8:
            return try ZipInflate.inflate(payload, uncompressedSize: entry.uncompressedSize)
        default:
            throw DocumentExtractionError.unreadableWord
        }
    }

    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let maxComment = min(65_535, data.count - 22)
        for comment in 0...maxComment {
            let offset = data.count - 22 - comment
            if data.u32(offset) == 0x06054b50 {
                let recordedComment = Int(data.u16(offset + 20))
                if recordedComment == comment {
                    return offset
                }
            }
        }
        return nil
    }

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }
}

private enum ZipInflate {
    static func inflate(_ input: Data, uncompressedSize: Int) throws -> Data {
        let capacity = max(uncompressedSize, 1)
        var output = Data(count: capacity)
        var stream = z_stream()
        var produced = 0
        var status: Int32 = Z_ERRNO

        input.withUnsafeBytes { srcBuffer in
            guard let src = srcBuffer.bindMemory(to: Bytef.self).baseAddress else {
                status = Z_DATA_ERROR
                return
            }
            stream.next_in = UnsafeMutablePointer(mutating: src)
            stream.avail_in = uInt(input.count)
            let initStatus = inflateInit2_(
                &stream,
                -MAX_WBITS,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                status = initStatus
                return
            }
            status = output.withUnsafeMutableBytes { dstBuffer in
                stream.next_out = dstBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(capacity)
                return zlib.inflate(&stream, Z_FINISH)
            }
            produced = Int(stream.total_out)
            inflateEnd(&stream)
        }

        guard status == Z_STREAM_END || status == Z_OK else {
            throw DocumentExtractionError.unreadableWord
        }
        output.count = produced
        return output
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
