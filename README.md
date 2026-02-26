# SGLocalLogger

一个面向 iOS 的本地日志 Swift Package，目标是：简洁、安全、高效。

## 特性

- 支持日志级别：`trace / debug / info / warning / error / fault`
- 所有级别统一落盘（不会因为级别过滤而丢失文件日志）
- 可配置是否打印到控制台，以及控制台最小输出级别
- 每条日志自动添加 ISO 8601（毫秒）时间前缀
- 支持日志文件大小轮转，避免单文件过大
- 支持按保留时长自动清理旧日志
- 支持按指定时间范围导出日志为 `.zip`
- 对外 API 为同步接口（不暴露 async/await）

## 环境要求

- iOS 15+
- Swift 6.2+

## 安装（Swift Package Manager）

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://your.git.repo/SGLocalLogger.git", from: "1.0.0")
]
```

并在 target 中引入：

```swift
dependencies: [
    .product(name: "SGLocalLogger", package: "SGLocalLogger")
]
```

## 快速开始

默认情况下，日志目录为：

- `Caches/SGLocalLogger`

你可以直接使用默认配置；`logsDirectory` 是可选覆盖项。

```swift
import Foundation
import SGLocalLogger

let logger = SGLocalLogger(
    configuration: LoggerConfig(
        consoleEnabled: true,
        consoleMinimumLevel: .info,
        maxFileSizeBytes: 1_048_576,        // 1 MB
        retentionDuration: 7 * 24 * 60 * 60, // 7 天
        autoPurgeInterval: 60,              // 最多每 60 秒触发一次自动清理
        filePrefix: "app"
    )
)

logger.log(.info, "应用启动")
logger.log(.debug, "用户点击按钮", metadata: ["screen": "home", "action": "tap"])
logger.log(.error, "请求失败", metadata: ["code": "500"])

// 确保缓冲落盘（例如应用即将退出前）
logger.flush()
```

如需自定义日志目录：

```swift
let customDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    .appendingPathComponent("MyAppLogs", isDirectory: true)

let logger = SGLocalLogger(
    configuration: LoggerConfig(logsDirectory: customDir)
)
```

## API

```swift
public final class SGLocalLogger {
    public init(configuration: LoggerConfig = LoggerConfig())

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        metadata: [String: String] = [:]
    )

    public func setConsoleMinimumLevel(_ level: LogLevel)
    public func flush()
    public func purgeExpiredLogs()
    public func exportLogs(in interval: DateInterval) throws -> URL
}
```

## 导出指定时间范围日志（ZIP）

```swift
let interval = DateInterval(
    start: Date().addingTimeInterval(-24 * 60 * 60),
    end: Date()
)

do {
    let zipURL = try logger.exportLogs(in: interval)
    print("ZIP 导出成功: \(zipURL.path)")
} catch SGLocalLoggerError.noLogsInRequestedInterval {
    print("该时间范围内没有日志")
} catch {
    print("导出失败: \(error)")
}
```

## 日志格式

示例：

```text
[2026-02-26T15:18:55.313Z] [INFO] 应用启动
[2026-02-26T15:18:56.101Z] [ERROR] 请求失败 code=500 endpoint=/v1/user
```

## 设计说明

- 外部调用全同步，内部使用串行队列保证线程安全
- `log(...)` 为无抛错 API：写盘失败会被吞掉，避免日志影响主业务流程
- 自动清理按间隔节流，减少频繁 I/O
- ZIP 导出采用系统能力实现，无第三方依赖

## 测试

```bash
swift test
```

