import Foundation
import Combine

@MainActor
final class AppContainer {
    let sampleStream: SampleStream
    let repository: SampleRepositoryHolder
    private let downsampler: Downsampler?
    private let sampler: PowerSampler
    private var bag: Set<AnyCancellable> = []

    init() {
        let sampler = PowerSampler()
        self.sampler = sampler
        self.sampleStream = SampleStream(sampler: sampler)

        let dbURL = AppContainer.databaseURL()
        let db = try? Database(url: dbURL)
        if let db {
            let repo = SampleRepository(db: db)
            self.repository = SampleRepositoryHolder(repository: repo, isAvailable: true)
            self.downsampler = Downsampler(repository: repo)
        } else {
            self.repository = SampleRepositoryHolder(repository: nil, isAvailable: false)
            self.downsampler = nil
        }
    }

    func start() {
        sampler.start()

        if let repo = repository.repository {
            sampler.onSample = { sample in
                Task { try? await repo.insert(sample) }
            }
        }
        Task { await downsampler?.start() }
    }

    func stop() {
        sampler.stop()
        Task { await downsampler?.stop() }
    }

    static func databaseURL() -> URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let dir = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support"))
            .appendingPathComponent("ChargeWatch", isDirectory: true)
        return dir.appendingPathComponent("data.sqlite")
    }
}

@MainActor
final class SampleRepositoryHolder: ObservableObject {
    let repository: SampleRepository?
    let isAvailable: Bool
    init(repository: SampleRepository?, isAvailable: Bool) {
        self.repository = repository
        self.isAvailable = isAvailable
    }
}
