import Foundation
import Combine

@MainActor
final class SampleStream: ObservableObject {
    @Published var latest: PowerSample?
    @Published var rolling: [PowerSample] = []

    private var bag: Set<AnyCancellable> = []

    init(sampler: PowerSampler) {
        sampler.$latest
            .receive(on: RunLoop.main)
            .assign(to: \.latest, on: self)
            .store(in: &bag)
        sampler.$rolling
            .receive(on: RunLoop.main)
            .assign(to: \.rolling, on: self)
            .store(in: &bag)
    }
}
