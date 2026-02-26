import Foundation

struct LogExport {
    let fileManager: FileManager
    let zipWriter: ZipArchiveWriter

    init(fileManager: FileManager = .default, zipWriter: ZipArchiveWriter = .init()) {
        self.fileManager = fileManager
        self.zipWriter = zipWriter
    }

    func selectFiles(in files: [URL], interval: DateInterval) -> [URL] {
        files.filter { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modifiedAt = values?.contentModificationDate ?? values?.creationDate
            guard let modifiedAt else {
                return false
            }
            return interval.contains(modifiedAt)
        }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    func export(
        files: [URL],
        in interval: DateInterval,
        filePrefix: String
    ) throws -> URL {
        let tempDirectory = fileManager.temporaryDirectory
        let name = "\(filePrefix)-\(Int(interval.start.timeIntervalSince1970))-\(Int(interval.end.timeIntervalSince1970)).zip"
        let zipURL = tempDirectory.appendingPathComponent(name, isDirectory: false)

        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        try zipWriter.writeArchive(at: zipURL, files: files)
        return zipURL
    }
}
