import Foundation

public struct LoggerConfig: Sendable {
    public var logsDirectory: URL
    public var consoleEnabled: Bool
    public var consoleMinimumLevel: LogLevel
    public var maxFileSizeBytes: Int
    public var retentionDuration: TimeInterval
    public var autoPurgeInterval: TimeInterval
    public var filePrefix: String

    public init(
        logsDirectory: URL = LoggerConfig.defaultLogsDirectory(),
        consoleEnabled: Bool = true,
        consoleMinimumLevel: LogLevel = .info,
        maxFileSizeBytes: Int = 1_048_576,
        retentionDuration: TimeInterval = 7 * 24 * 60 * 60,
        autoPurgeInterval: TimeInterval = 60,
        filePrefix: String = "sglog"
    ) {
        self.logsDirectory = logsDirectory
        self.consoleEnabled = consoleEnabled
        self.consoleMinimumLevel = consoleMinimumLevel
        self.maxFileSizeBytes = max(4_096, maxFileSizeBytes)
        self.retentionDuration = max(0, retentionDuration)
        self.autoPurgeInterval = max(0, autoPurgeInterval)
        self.filePrefix = filePrefix
    }

    public static func defaultLogsDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SGLocalLogger", isDirectory: true)
    }
}
