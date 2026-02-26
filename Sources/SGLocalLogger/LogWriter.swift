import Foundation

final class LogWriter {
    private let fileManager: FileManager
    private let logsDirectory: URL
    private let filePrefix: String
    private let maxFileSizeBytes: Int

    private var fileHandle: FileHandle?
    private var currentFileURL: URL?
    private var currentFileSize: Int = 0

    init(fileManager: FileManager = .default, config: LoggerConfig) {
        self.fileManager = fileManager
        self.logsDirectory = config.logsDirectory
        self.filePrefix = config.filePrefix
        self.maxFileSizeBytes = config.maxFileSizeBytes
    }

    deinit {
        fileHandle?.closeFile()
    }

    func write(line: String) throws {
        try ensureLogDirectoryExists()

        let lineWithBreak = line + "\n"
        guard let data = lineWithBreak.data(using: .utf8) else { return }
        try rotateIfNeeded(incomingBytes: data.count)

        if fileHandle == nil {
            try openNewFile()
        }

        fileHandle?.write(data)
        currentFileSize += data.count
    }

    func flush() throws {
        fileHandle?.synchronizeFile()
    }

    func listLogFiles() throws -> [URL] {
        try ensureLogDirectoryExists()
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let files = try fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        return files.filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix(filePrefix) }
    }

    private func rotateIfNeeded(incomingBytes: Int) throws {
        if fileHandle == nil {
            return
        }

        if currentFileSize + incomingBytes <= maxFileSizeBytes {
            return
        }

        fileHandle?.closeFile()
        fileHandle = nil
        currentFileURL = nil
        currentFileSize = 0
    }

    private func openNewFile() throws {
        let fileURL = makeNewFileURL()
        if !fileManager.createFile(atPath: fileURL.path, contents: nil) {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        self.fileHandle = handle
        self.currentFileURL = fileURL
        self.currentFileSize = 0
    }

    private func ensureLogDirectoryExists() throws {
        if fileManager.fileExists(atPath: logsDirectory.path) {
            return
        }

        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private func makeNewFileURL() -> URL {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let uuid = UUID().uuidString.lowercased()
        let fileName = "\(filePrefix)-\(ts)-\(uuid).log"
        return logsDirectory.appendingPathComponent(fileName, isDirectory: false)
    }
}
