import Foundation
import zlib

nonisolated struct XLSXParserService: Sendable {

    static func parseToCSV(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let bytes = [UInt8](data)
        guard let entries = ZIPDirectory.parse(bytes: bytes) else { return nil }

        var sharedStrings: [String] = []
        if let ssEntry = entries["xl/sharedStrings.xml"],
           let ssBytes = ZIPDirectory.extract(entry: ssEntry, from: bytes) {
            sharedStrings = SharedStringsXMLParser.parse(data: Data(ssBytes))
        }

        let sheetEntry = entries["xl/worksheets/sheet1.xml"] ?? entries["xl/worksheets/Sheet1.xml"]
        guard let entry = sheetEntry,
              let sheetBytes = ZIPDirectory.extract(entry: entry, from: bytes) else { return nil }

        return SheetXMLParser.parseToCSV(data: Data(sheetBytes), sharedStrings: sharedStrings)
    }
}

// MARK: - ZIP Reader

private struct ZIPEntry {
    let localHeaderOffset: Int
    let compressedSize: Int
    let uncompressedSize: Int
    let method: UInt16
}

private enum ZIPDirectory {

    static func parse(bytes: [UInt8]) -> [String: ZIPEntry]? {
        guard let eocdOffset = findEOCD(bytes: bytes) else { return nil }
        guard eocdOffset + 22 <= bytes.count else { return nil }

        let cdOffset = le32(bytes: bytes, at: eocdOffset + 16)
        let cdCount  = le16(bytes: bytes, at: eocdOffset + 10)
        guard Int(cdOffset) < bytes.count else { return nil }

        var pos = Int(cdOffset)
        var entries: [String: ZIPEntry] = [:]

        for _ in 0..<cdCount {
            guard pos + 46 <= bytes.count else { break }
            guard le32(bytes: bytes, at: pos) == 0x02014B50 else { break }

            let method          = le16(bytes: bytes, at: pos + 10)
            let compressedSize  = Int(le32(bytes: bytes, at: pos + 20))
            let uncompressedSz  = Int(le32(bytes: bytes, at: pos + 24))
            let nameLen         = Int(le16(bytes: bytes, at: pos + 28))
            let extraLen        = Int(le16(bytes: bytes, at: pos + 30))
            let commentLen      = Int(le16(bytes: bytes, at: pos + 32))
            let localOffset     = Int(le32(bytes: bytes, at: pos + 42))

            guard pos + 46 + nameLen <= bytes.count else { break }
            let nameSlice = bytes[(pos + 46)..<(pos + 46 + nameLen)]
            let name = String(bytes: nameSlice, encoding: .utf8) ?? String(bytes: nameSlice, encoding: .isoLatin1) ?? ""

            entries[name] = ZIPEntry(
                localHeaderOffset: localOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSz,
                method: method
            )
            pos += 46 + nameLen + extraLen + commentLen
        }

        return entries.isEmpty ? nil : entries
    }

    static func extract(entry: ZIPEntry, from bytes: [UInt8]) -> [UInt8]? {
        let lh = entry.localHeaderOffset
        guard lh + 30 <= bytes.count else { return nil }
        guard le32(bytes: bytes, at: lh) == 0x04034B50 else { return nil }

        let nameLen  = Int(le16(bytes: bytes, at: lh + 26))
        let extraLen = Int(le16(bytes: bytes, at: lh + 28))
        let dataStart = lh + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= bytes.count else { return nil }

        let compressed = Array(bytes[dataStart..<(dataStart + entry.compressedSize)])

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return inflateRaw(input: compressed, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    private static func inflateRaw(input: [UInt8], expectedSize: Int) -> [UInt8]? {
        guard expectedSize > 0 else { return [] }
        var output = [UInt8](repeating: 0, count: expectedSize)

        let result: Int32 = input.withUnsafeBytes { inBuf -> Int32 in
            guard let inPtr = inBuf.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            return output.withUnsafeMutableBytes { outBuf -> Int32 in
                guard let outPtr = outBuf.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
                var stream = z_stream()
                stream.next_in   = UnsafeMutablePointer(mutating: inPtr)
                stream.avail_in  = uInt(input.count)
                stream.next_out  = outPtr
                stream.avail_out = uInt(expectedSize)
                guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                    return Z_DATA_ERROR
                }
                let status = inflate(&stream, Z_FINISH)
                inflateEnd(&stream)
                return status
            }
        }

        guard result == Z_STREAM_END || result == Z_OK || result == Z_BUF_ERROR else { return nil }
        return output
    }

    private static func findEOCD(bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let searchStart = max(0, bytes.count - 65558)
        var i = bytes.count - 22
        while i >= searchStart {
            if bytes[i] == 0x50 && bytes[i+1] == 0x4B && bytes[i+2] == 0x05 && bytes[i+3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func le16(bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func le32(bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

// MARK: - Shared Strings XML Parser

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    nonisolated(unsafe) var strings: [String] = []
    nonisolated(unsafe) private var currentText = ""
    nonisolated(unsafe) private var inT = false

    nonisolated static func parse(data: Data) -> [String] {
        let parser = XMLParser(data: data)
        let delegate = SharedStringsXMLParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String,
                            namespaceURI: String?, qualifiedName: String?,
                            attributes: [String: String] = [:]) {
        if elementName == "si" { currentText = "" }
        else if elementName == "t" { inT = true }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { currentText += string }
    }

    nonisolated func parser(_ parser: XMLParser, didEndElement elementName: String,
                            namespaceURI: String?, qualifiedName: String?) {
        if elementName == "t" {
            inT = false
        } else if elementName == "si" {
            strings.append(currentText)
        }
    }
}

// MARK: - Sheet XML Parser

private final class SheetXMLParser: NSObject, XMLParserDelegate {
    nonisolated(unsafe) var csvLines: [String] = []
    nonisolated(unsafe) private var sharedStrings: [String] = []
    nonisolated(unsafe) private var currentRow: [String] = []
    nonisolated(unsafe) private var currentValue = ""
    nonisolated(unsafe) private var currentType = ""
    nonisolated(unsafe) private var inV = false
    nonisolated(unsafe) private var inIS = false

    nonisolated static func parseToCSV(data: Data, sharedStrings: [String]) -> String? {
        let parser = XMLParser(data: data)
        let delegate = SheetXMLParser()
        delegate.sharedStrings = sharedStrings
        parser.delegate = delegate
        parser.parse()
        let result = delegate.csvLines.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String,
                            namespaceURI: String?, qualifiedName: String?,
                            attributes: [String: String] = [:]) {
        switch elementName {
        case "row": currentRow = []
        case "c":   currentValue = ""; currentType = attributes["t"] ?? ""
        case "v":   inV = true
        case "is":  inIS = true
        default: break
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV || inIS { currentValue += string }
    }

    nonisolated func parser(_ parser: XMLParser, didEndElement elementName: String,
                            namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v":
            inV = false
        case "is":
            inIS = false
        case "c":
            let value: String
            if currentType == "s", let idx = Int(currentValue), idx < sharedStrings.count {
                value = sharedStrings[idx]
            } else {
                value = currentValue
            }
            currentRow.append(csvEscape(value))
        case "row":
            csvLines.append(currentRow.joined(separator: ","))
        default:
            break
        }
    }

    nonisolated private func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
