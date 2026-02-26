import Foundation
#if os(iOS) && canImport(AppleArchive) && canImport(System)
import AppleArchive
import System
#endif

struct AppleEncryptedArchiveExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func exportEncryptedArchive(
        files: [URL],
        interval: DateInterval,
        filePrefix: String,
        password: String
    ) throws -> URL {
        guard !password.isEmpty else {
            throw CocoaError(.coderInvalidValue)
        }

        #if os(iOS) && canImport(AppleArchive) && canImport(System)
        let stagingDir = fileManager.temporaryDirectory
            .appendingPathComponent("\(filePrefix)-staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDir) }

        for file in files {
            let destination = stagingDir.appendingPathComponent(file.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file, to: destination)
        }

        let archiveName = "\(filePrefix)-\(Int(interval.start.timeIntervalSince1970))-\(Int(interval.end.timeIntervalSince1970)).aea"
        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(archiveName, isDirectory: false)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        let encryptionContext = ArchiveEncryptionContext(
            profile: .hkdf_sha256_aesctr_hmac__scrypt__none,
            compressionAlgorithm: .lzfse,
            compressionBlockSize: 64 * 1024
        )
        try encryptionContext.setPassword(password)

        let destinationPath = FilePath(archiveURL.path)
        let sourcePath = FilePath(stagingDir.path)

        try ArchiveByteStream.withFileStream(
            path: destinationPath,
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: .ownerReadWrite
        ) { fileStream in
            guard let encryptedStream = ArchiveByteStream.encryptionStream(
                writingTo: fileStream,
                encryptionContext: encryptionContext,
                flags: [],
                threadCount: 1
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            try ArchiveStream.withEncodeStream(
                writingTo: encryptedStream,
                selectUsing: nil,
                flags: [],
                threadCount: 1
            ) { archiveStream in
                try archiveStream.writeDirectoryContents(
                    archiveFrom: sourcePath,
                    path: nil,
                    keySet: .defaultForArchive,
                    selectUsing: nil,
                    flags: [],
                    threadCount: 1
                )
            }

            try encryptedStream.close(updatingContext: encryptionContext)
        }

        return archiveURL
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }
}
