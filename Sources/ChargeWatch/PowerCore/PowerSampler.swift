import Foundation
import Combine
import IOKit
import IOKit.ps

@MainActor
final class PowerSampler: ObservableObject {
    @Published private(set) var latest: PowerSample?
    @Published private(set) var rolling: [PowerSample] = []

    private let reader: IORegistryReader
    private let interval: TimeInterval
    private let rollingCapacity: Int
    private var timer: DispatchSourceTimer?
    private var notifyRunLoopSource: CFRunLoopSource?

    var onSample: ((PowerSample) -> Void)?

    init(reader: IORegistryReader = IORegistryReader(),
         interval: TimeInterval = 1.0,
         rollingCapacity: Int = 60) {
        self.reader = reader
        self.interval = interval
        self.rollingCapacity = rollingCapacity
    }

    func start() {
        sampleOnce()
        startTimer()
        startPowerNotifications()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let src = notifyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            notifyRunLoopSource = nil
        }
    }

    private func startTimer() {
        let q = DispatchQueue(label: "chargewatch.sampler", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.sampleOnce() }
        }
        t.resume()
        self.timer = t
    }

    private func startPowerNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerSampler>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in me.sampleOnce() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        notifyRunLoopSource = source
    }

    private func sampleOnce() {
        let sample = reader.read()
        latest = sample
        rolling.append(sample)
        if rolling.count > rollingCapacity {
            rolling.removeFirst(rolling.count - rollingCapacity)
        }
        onSample?(sample)
    }
}
