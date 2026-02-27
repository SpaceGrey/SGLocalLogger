import Foundation

public enum SGLocalLoggerError: Error {
    case noLogsInRequestedInterval
    /// 加密导出时密码无效（如过短）。Apple Archive 建议密码至少 8 个字符。
    case invalidExportPassword
}

public final class SGLocalLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sglocallogger.core")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queueValue: UInt8 = 1

    private var config: LoggerConfig
    private let dateFormatting: DateFormatting
    private let writer: LogWriter
    private let retention: LogRetention
    private let exporter: LogExport
    private let encryptedExporter: AppleEncryptedArchiveExporter

    private var lastPurgeDate: Date

    public init(configuration: LoggerConfig = LoggerConfig()) {
        self.config = configuration
        self.dateFormatting = DateFormatting()
        self.writer = LogWriter(config: configuration)
        self.retention = LogRetention()
        self.exporter = LogExport()
        self.encryptedExporter = AppleEncryptedArchiveExporter()
        self.lastPurgeDate = .distantPast
        self.queue.setSpecific(key: queueKey, value: queueValue)
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        metadata: [String: String] = [:]
    ) {
        onQueueSync {
            let now = Date()
            let line = buildLogLine(level: level, message: message(), metadata: metadata, date: now)

            if config.consoleEnabled && level >= config.consoleMinimumLevel {
                print(line)
            }

            do {
                try writer.write(line: line)
                maybePurgeExpiredLogs(referenceDate: now)
            } catch {
                // Preserve a safe, non-throwing API; failed writes are intentionally swallowed.
            }
        }
    }

    public func setConsoleMinimumLevel(_ level: LogLevel) {
        onQueueSync {
            config.consoleMinimumLevel = level
        }
    }

    public func flush() {
        onQueueSync {
            try? writer.flush()
        }
    }

    @available(iOS 15.0, macOS 10.15, *)
    public func flushAsync() async {
        await withCheckedContinuation { continuation in
            queue.async {
                try? self.writer.flush()
                continuation.resume()
            }
        }
    }

    public func purgeExpiredLogs() {
        onQueueSync {
            purgeExpiredLogsLocked(referenceDate: Date())
        }
    }

    @available(iOS 15.0, macOS 10.15, *)
    public func purgeExpiredLogsAsync() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.purgeExpiredLogsLocked(referenceDate: Date())
                continuation.resume()
            }
        }
    }

    public func exportLogs(in interval: DateInterval) throws -> URL {
        try onQueueSyncThrowing {
            let allFiles = try writer.listLogFiles()
            let selectedFiles = exporter.selectFiles(in: allFiles, interval: interval)
            guard !selectedFiles.isEmpty else {
                throw SGLocalLoggerError.noLogsInRequestedInterval
            }
            return try exporter.export(files: selectedFiles, in: interval, filePrefix: config.filePrefix)
        }
    }

    @available(iOS 15.0, macOS 10.15, *)
    public func exportLogsAsync(in interval: DateInterval) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let allFiles = try self.writer.listLogFiles()
                    let selectedFiles = self.exporter.selectFiles(in: allFiles, interval: interval)
                    guard !selectedFiles.isEmpty else {
                        throw SGLocalLoggerError.noLogsInRequestedInterval
                    }
                    let url = try self.exporter.export(files: selectedFiles, in: interval, filePrefix: self.config.filePrefix)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func exportEncryptedLogs(in interval: DateInterval, password: String) throws -> URL {
        try onQueueSyncThrowing {
            let allFiles = try writer.listLogFiles()
            let selectedFiles = exporter.selectFiles(in: allFiles, interval: interval)
            guard !selectedFiles.isEmpty else {
                throw SGLocalLoggerError.noLogsInRequestedInterval
            }
            return try encryptedExporter.exportEncryptedArchive(
                files: selectedFiles,
                interval: interval,
                filePrefix: config.filePrefix,
                password: password
            )
        }
    }

    @available(iOS 15.0, macOS 10.15, *)
    public func exportEncryptedLogsAsync(in interval: DateInterval, password: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let allFiles = try self.writer.listLogFiles()
                    let selectedFiles = self.exporter.selectFiles(in: allFiles, interval: interval)
                    guard !selectedFiles.isEmpty else {
                        throw SGLocalLoggerError.noLogsInRequestedInterval
                    }
                    let url = try self.encryptedExporter.exportEncryptedArchive(
                        files: selectedFiles,
                        interval: interval,
                        filePrefix: self.config.filePrefix,
                        password: password
                    )
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func maybePurgeExpiredLogs(referenceDate: Date) {
        guard config.autoPurgeInterval > 0 else {
            return
        }

        if referenceDate.timeIntervalSince(lastPurgeDate) >= config.autoPurgeInterval {
            purgeExpiredLogsLocked(referenceDate: referenceDate)
        }
    }

    private func purgeExpiredLogsLocked(referenceDate: Date) {
        guard let files = try? writer.listLogFiles() else {
            return
        }
        _ = retention.purgeExpiredFiles(
            in: files,
            referenceDate: referenceDate,
            retentionDuration: config.retentionDuration
        )
        lastPurgeDate = referenceDate
    }

    private func buildLogLine(
        level: LogLevel,
        message: String,
        metadata: [String: String],
        date: Date
    ) -> String {
        let ts = dateFormatting.timestampString(for: date)
        if metadata.isEmpty {
            return "[\(ts)] [\(level.uppercaseName)] \(message)"
        }

        let metadataString = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "[\(ts)] [\(level.uppercaseName)] \(message) \(metadataString)"
    }

    private func onQueueSync<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueValue {
            return block()
        }
        return queue.sync(execute: block)
    }

    private func onQueueSyncThrowing<T>(_ block: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueValue {
            return try block()
        }
        return try queue.sync(execute: block)
    }
}
