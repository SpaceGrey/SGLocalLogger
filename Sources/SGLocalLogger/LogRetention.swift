import Foundation

struct LogRetention {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func purgeExpiredFiles(
        in files: [URL],
        referenceDate: Date,
        retentionDuration: TimeInterval
    ) -> Int {
        let expiryDate = referenceDate.addingTimeInterval(-retentionDuration)
        var removedCount = 0

        for url in files {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modifiedAt = values?.contentModificationDate ?? values?.creationDate
            guard let modifiedAt else {
                continue
            }

            if modifiedAt < expiryDate {
                do {
                    try fileManager.removeItem(at: url)
                    removedCount += 1
                } catch {
                    continue
                }
            }
        }

        return removedCount
    }
}
