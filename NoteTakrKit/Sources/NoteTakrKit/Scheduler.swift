import Foundation

public protocol Scheduler {
    func schedule(id: String, delay: TimeInterval, work: @escaping () -> Void)
    func cancel(id: String)
}

public final class FoundationScheduler: Scheduler {
    private var timers: [String: Timer] = [:]

    public init() {}

    public func schedule(id: String, delay: TimeInterval, work: @escaping () -> Void) {
        timers[id]?.invalidate()
        timers[id] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.timers.removeValue(forKey: id)
            work()
        }
    }

    public func cancel(id: String) {
        timers[id]?.invalidate()
        timers[id] = nil
    }
}
