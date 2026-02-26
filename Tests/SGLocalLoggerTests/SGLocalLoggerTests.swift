import Foundation
import XCTest
@testable import SGLocalLogger

final class SGLocalLoggerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SGLocalLoggerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testAllLevelsArePersisted() throws {
        let logger = makeLogger(consoleMinimumLevel: .fault)

        logger.log(.trace, "trace-message")
        logger.log(.debug, "debug-message")
        logger.log(.info, "info-message")
        logger.log(.warning, "warning-message")
        logger.log(.error, "error-message")
        logger.log(.fault, "fault-message")
        logger.flush()

        let content = try readAllLogContent()
        XCTAssertTrue(content.contains("trace-message"))
        XCTAssertTrue(content.contains("debug-message"))
        XCTAssertTrue(content.contains("info-message"))
        XCTAssertTrue(content.contains("warning-message"))
        XCTAssertTrue(content.contains("error-message"))
        XCTAssertTrue(content.contains("fault-message"))
    }

    func testLogLineHasTimestampPrefix() throws {
        let logger = makeLogger()
        logger.log(.info, "timestamp-check")
        logger.flush()

        let content = try readAllLogContent()
        guard let firstLine = content.split(separator: "\n").first else {
            XCTFail("Expected at least one log line")
            return
        }

        let pattern = #"^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z\] \[INFO\] "#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: firstLine.utf16.count)
        XCTAssertNotNil(regex.firstMatch(in: String(firstLine), range: range))
    }

    func testPurgeExpiredLogsRemovesOldFiles() throws {
        let logger = makeLogger(retentionDuration: 1, autoPurgeInterval: 0)
        logger.log(.info, "old-log")
        logger.flush()

        let files = try listLogFiles()
        XCTAssertEqual(files.count, 1)

        let oldDate = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: files[0].path)
        logger.purgeExpiredLogs()

        let remaining = try listLogFiles()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testExportLogsCreatesZip() throws {
        let logger = makeLogger()
        logger.log(.info, "export-message")
        logger.flush()

        let interval = DateInterval(start: Date(timeIntervalSinceNow: -60), end: Date(timeIntervalSinceNow: 60))
        let zipURL = try logger.exportLogs(in: interval)

        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        let data = try Data(contentsOf: zipURL)
        XCTAssertGreaterThan(data.count, 4)
        XCTAssertEqual(data[0], 0x50)
        XCTAssertEqual(data[1], 0x4B)
    }

    func testExportWithoutMatchedLogsThrows() throws {
        let logger = makeLogger()
        logger.log(.info, "new-log")
        logger.flush()

        let interval = DateInterval(start: Date(timeIntervalSinceNow: -7200), end: Date(timeIntervalSinceNow: -3600))
        XCTAssertThrowsError(try logger.exportLogs(in: interval))
    }

    func testExportEncryptedLogsCreatesArchiveFile() throws {
        #if os(iOS)
        let logger = makeLogger()
        logger.log(.info, "encrypted-export-message")
        logger.flush()

        let interval = DateInterval(start: Date(timeIntervalSinceNow: -60), end: Date(timeIntervalSinceNow: 60))
        let archiveURL = try logger.exportEncryptedLogs(in: interval, password: "test-password-123")

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(archiveURL.pathExtension, "aea")
        let data = try Data(contentsOf: archiveURL)
        XCTAssertGreaterThan(data.count, 16)
        #else
        throw XCTSkip("AppleArchive encrypted export test runs on iOS only.")
        #endif
    }

    private func makeLogger(
        consoleMinimumLevel: LogLevel = .info,
        retentionDuration: TimeInterval = 3600,
        autoPurgeInterval: TimeInterval = 120
    ) -> SGLocalLogger {
        let config = LoggerConfig(
            logsDirectory: tempDirectory,
            consoleEnabled: false,
            consoleMinimumLevel: consoleMinimumLevel,
            maxFileSizeBytes: 128 * 1024,
            retentionDuration: retentionDuration,
            autoPurgeInterval: autoPurgeInterval,
            filePrefix: "testlog"
        )
        return SGLocalLogger(configuration: config)
    }

    private func listLogFiles() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return files
            .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("testlog") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readAllLogContent() throws -> String {
        let files = try listLogFiles()
        return try files.reduce(into: "") { partialResult, url in
            partialResult += try String(contentsOf: url, encoding: .utf8)
        }
    }
}
