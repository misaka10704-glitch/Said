import Foundation
import zlib

enum ZipError: Error {
    case openFailed
    case readFailed
    case writeFailed
    case invalidArchive
}

/// Minimal ZIP reader/writer for .apkg (stored + deflated entries).
enum SimpleZip {
    static func unzip(archiveURL: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let data = try Data(contentsOf: archiveURL)
        var offset = 0
        while offset + 30 <= data.count {
            let sig = readU32(data, offset)
            if sig != 0x04034b50 { break }
            let flags = Int(readU16(data, offset + 6))
            let method = Int(readU16(data, offset + 8))
            var compSize = Int(readU32(data, offset + 18))
            var uncompSize = Int(readU32(data, offset + 22))
            let nameLen = Int(readU16(data, offset + 26))
            let extraLen = Int(readU16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else { throw ZipError.invalidArchive }
            let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? "file"
            var dataStart = nameEnd + extraLen

            // Data descriptor (bit 3): sizes after data — rare in apkg; skip if sizes are zero and flag set
            if (flags & 0x8) != 0 && compSize == 0 {
                throw ZipError.invalidArchive
            }
            guard dataStart + compSize <= data.count else { throw ZipError.invalidArchive }
            let compressed = data.subdata(in: dataStart..<(dataStart + compSize))
            let outURL = destination.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: outURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let payload: Data
                switch method {
                case 0: payload = compressed
                case 8: payload = try inflateRaw(compressed, expectedSize: max(uncompSize, 1))
                default: throw ZipError.invalidArchive
                }
                try payload.write(to: outURL)
                _ = uncompSize
            }
            offset = dataStart + compSize
        }
    }

    static func zip(directory: URL, to archiveURL: URL) throws {
        var entries: [(String, Data)] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw ZipError.readFailed
        }
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let rel = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
            entries.append((rel, try Data(contentsOf: fileURL)))
        }

        var localParts = Data()
        var central = Data()
        var offset: UInt32 = 0
        for (name, fileData) in entries {
            let nameData = Data(name.utf8)
            // Prefer store for SQLite reliability / simplicity on device
            let payload = fileData
            let method: UInt16 = 0
            let crc = crc32(fileData)
            var local = Data()
            appendU32(&local, 0x04034b50)
            appendU16(&local, 20)
            appendU16(&local, 0)
            appendU16(&local, method)
            appendU16(&local, 0)
            appendU16(&local, 0)
            appendU32(&local, crc)
            appendU32(&local, UInt32(payload.count))
            appendU32(&local, UInt32(fileData.count))
            appendU16(&local, UInt16(nameData.count))
            appendU16(&local, 0)
            local.append(nameData)
            local.append(payload)

            var cen = Data()
            appendU32(&cen, 0x02014b50)
            appendU16(&cen, 20)
            appendU16(&cen, 20)
            appendU16(&cen, 0)
            appendU16(&cen, method)
            appendU16(&cen, 0)
            appendU16(&cen, 0)
            appendU32(&cen, crc)
            appendU32(&cen, UInt32(payload.count))
            appendU32(&cen, UInt32(fileData.count))
            appendU16(&cen, UInt16(nameData.count))
            appendU16(&cen, 0)
            appendU16(&cen, 0)
            appendU16(&cen, 0)
            appendU16(&cen, 0)
            appendU32(&cen, 0)
            appendU32(&cen, offset)
            cen.append(nameData)

            localParts.append(local)
            central.append(cen)
            offset += UInt32(local.count)
        }

        var end = Data()
        appendU32(&end, 0x06054b50)
        appendU16(&end, 0)
        appendU16(&end, 0)
        appendU16(&end, UInt16(entries.count))
        appendU16(&end, UInt16(entries.count))
        appendU32(&end, UInt32(central.count))
        appendU32(&end, UInt32(localParts.count))
        appendU16(&end, 0)

        var out = Data()
        out.append(localParts)
        out.append(central)
        out.append(end)
        try out.write(to: archiveURL)
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func appendU16(_ data: inout Data, _ v: UInt16) {
        data.append(UInt8(v & 0xff))
        data.append(UInt8((v >> 8) & 0xff))
    }

    private static func appendU32(_ data: inout Data, _ v: UInt32) {
        data.append(UInt8(v & 0xff))
        data.append(UInt8((v >> 8) & 0xff))
        data.append(UInt8((v >> 16) & 0xff))
        data.append(UInt8((v >> 24) & 0xff))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buf -> UInt32 in
            let ptr = buf.bindMemory(to: Bytef.self).baseAddress
            return UInt32(zlib.crc32(0, ptr, uInt(data.count)))
        }
    }

    private static func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ZipError.readFailed }
        defer { _ = inflateEnd(&stream) }

        var capacity = max(expectedSize, input.count * 8, 4096)
        var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        try input.withUnsafeBytes { (srcBuf: UnsafeRawBufferPointer) in
            guard let src = srcBuf.bindMemory(to: Bytef.self).baseAddress else { throw ZipError.readFailed }
            stream.next_in = UnsafeMutablePointer(mutating: src)
            stream.avail_in = uInt(input.count)
            stream.next_out = buffer
            stream.avail_out = uInt(capacity)

            while true {
                status = zlib.inflate(&stream, Z_NO_FLUSH)
                if status == Z_STREAM_END {
                    return
                }
                if status == Z_OK || status == Z_BUF_ERROR {
                    if stream.avail_out == 0 {
                        let produced = Int(stream.total_out)
                        let newCap = capacity * 2
                        let grown = UnsafeMutablePointer<UInt8>.allocate(capacity: newCap)
                        grown.moveInitialize(from: buffer, count: produced)
                        buffer.deallocate()
                        buffer = grown
                        capacity = newCap
                        stream.next_out = buffer.advanced(by: produced)
                        stream.avail_out = uInt(capacity - produced)
                        continue
                    }
                    if status == Z_BUF_ERROR && stream.avail_in == 0 {
                        throw ZipError.readFailed
                    }
                    continue
                }
                throw ZipError.readFailed
            }
        }
        return Data(bytes: buffer, count: Int(stream.total_out))
    }
}
