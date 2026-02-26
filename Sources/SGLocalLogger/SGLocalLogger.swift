import Foundation

public enum SGLocalLoggerError: Error {
    case noLogsInRequestedInterval
}

public final class SGLocalLogger {
    private let queue = DispatchQueue(label: "com.sglocallogger.core")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queueValue: UInt8 = 1

    private var config: LoggerConfig
    private let dateFormatting: DateFormatting
    private let writer: LogWriter
    private let retention: LogRetention
    private let exporter: LogExport

    private var lastPurgeDate: Date

    public init(configuration: LoggerConfig = LoggerConfig()) {
        self.config = configuration
        self.dateFormatting = DateFormatting()
        self.writer = LogWriter(config: configuration)
        self.retention = LogRetention()
        self.exporter = LogExport()
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

    public func purgeExpiredLogs() {
        onQueueSync {
            purgeExpiredLogsLocked(referenceDate: Date())
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
