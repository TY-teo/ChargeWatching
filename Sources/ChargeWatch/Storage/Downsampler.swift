import Foundation

actor Downsampler {
    private let repository: SampleRepository
    private var timer: Task<Void, Never>?

    init(repository: SampleRepository) {
        self.repository = repository
    }

    func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                await self?.runOnce()
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func runOnce() async {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAgo = now.addingTimeInterval(-86400)
        let oneWeekAgo = now.addingTimeInterval(-86400 * 7)
        let oneMonthAgo = now.addingTimeInterval(-86400 * 30)

        do {
            try await repository.aggregateBucket(from: "samples_raw", to: "samples_10s",
                                                 bucketSeconds: 10, until: oneHourAgo)
            try await repository.purge(olderThan: oneDayAgo, table: "samples_raw")

            try await repository.aggregateBucket(from: "samples_10s", to: "samples_1min",
                                                 bucketSeconds: 60, until: oneDayAgo)
            try await repository.purge(olderThan: oneWeekAgo, table: "samples_10s")

            try await repository.aggregateBucket(from: "samples_1min", to: "samples_5min",
                                                 bucketSeconds: 300, until: oneWeekAgo)
            try await repository.purge(olderThan: oneMonthAgo, table: "samples_1min")
        } catch {
            NSLog("Downsampler error: \(error)")
        }
        await repository.checkpoint()
    }
}
