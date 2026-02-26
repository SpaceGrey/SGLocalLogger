import Foundation

struct ZipArchiveWriter {
    private struct Entry {
        let fileName: String
        let fileData: Data
        let crc32: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
        let localHeaderOffset: UInt32
    }

    func writeArchive(at destinationURL: URL, files: [URL]) throws {
        var archiveData = Data()
        var entries: [Entry] = []
        var usedFileNames = Set<String>()

        for (index, fileURL) in files.enumerated() {
            let originalName = fileURL.lastPathComponent
            let fileName = makeUniqueName(originalName, index: index, usedNames: &usedFileNames)
            let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let crc = CRC32.hash(of: fileData)
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modifiedAt = values?.contentModificationDate ?? values?.creationDate ?? Date()
            let (dosDate, dosTime) = Self.dosDateTime(from: modifiedAt)

            let offset = UInt32(archiveData.count)
            let fileNameData = Data(fileName.utf8)

            archiveData.appendLE(UInt32(0x04034b50))
            archiveData.appendLE(UInt16(20))
            archiveData.appendLE(UInt16(0))
            archiveData.appendLE(UInt16(0))
            archiveData.appendLE(dosTime)
            archiveData.appendLE(dosDate)
            archiveData.appendLE(crc)
            archiveData.appendLE(UInt32(fileData.count))
            archiveData.appendLE(UInt32(fileData.count))
            archiveData.appendLE(UInt16(fileNameData.count))
            archiveData.appendLE(UInt16(0))
            archiveData.append(fileNameData)
            archiveData.append(fileData)

            entries.append(
                Entry(
                    fileName: fileName,
                    fileData: fileData,
                    crc32: crc,
                    dosTime: dosTime,
                    dosDate: dosDate,
                    localHeaderOffset: offset
                )
            )
        }

        let centralDirectoryOffset = UInt32(archiveData.count)
        var centralDirectoryData = Data()

        for entry in entries {
            let fileNameData = Data(entry.fileName.utf8)
            centralDirectoryData.appendLE(UInt32(0x02014b50))
            centralDirectoryData.appendLE(UInt16(20))
            centralDirectoryData.appendLE(UInt16(20))
            centralDirectoryData.appendLE(UInt16(0))
            centralDirectoryData.appendLE(UInt16(0))
            centralDirectoryData.appendLE(entry.dosTime)
            centralDirectoryData.appendLE(entry.dosDate)
            centralDirectoryData.appendLE(entry.crc32)
            centralDirectoryData.appendLE(UInt32(entry.fileData.count))
            centralDirectoryData.appendLE(UInt32(entry.fileData.count))
            centralDirectoryData.appendLE(UInt16(fileNameData.count))
            centralDirectoryData.appendLE(UInt16(0))
            centralDirectoryData.appendLE(UInt16(0))
            centralDirectoryData.appendLE(UInt16(0))
            centralDirectoryData.appendLE(UInt16(0))
            centralDirectoryData.appendLE(UInt32(0))
            centralDirectoryData.appendLE(entry.localHeaderOffset)
            centralDirectoryData.append(fileNameData)
        }

        archiveData.append(centralDirectoryData)

        archiveData.appendLE(UInt32(0x06054b50))
        archiveData.appendLE(UInt16(0))
        archiveData.appendLE(UInt16(0))
        archiveData.appendLE(UInt16(entries.count))
        archiveData.appendLE(UInt16(entries.count))
        archiveData.appendLE(UInt32(centralDirectoryData.count))
        archiveData.appendLE(centralDirectoryOffset)
        archiveData.appendLE(UInt16(0))

        try archiveData.write(to: destinationURL, options: .atomic)
    }

    private func makeUniqueName(_ baseName: String, index: Int, usedNames: inout Set<String>) -> String {
        if !usedNames.contains(baseName) {
            usedNames.insert(baseName)
            return baseName
        }

        let extensionPart = (baseName as NSString).pathExtension
        let namePart = (baseName as NSString).deletingPathExtension
        let candidate = extensionPart.isEmpty
            ? "\(namePart)-\(index)"
            : "\(namePart)-\(index).\(extensionPart)"
        usedNames.insert(candidate)
        return candidate
    }

    private static func dosDateTime(from date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let year = max(1980, min(2107, components.year ?? 1980))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))

        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | (second / 2))
        return (dosDate, dosTime)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                if (value & 1) != 0 {
                    value = (value >> 1) ^ 0xEDB88320
                } else {
                    value = value >> 1
                }
            }
            return value
        }
    }()

    static func hash(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let tableIndex = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[tableIndex]
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { rawBuffer in
            append(rawBuffer.bindMemory(to: UInt8.self))
        }
    }
}
