import CoreGraphics
import Foundation

/// 디스플레이 구성 변경을 감시한다. 변경이 몰려서 오므로 잠깐 모아서 한 번만 알린다.
public final class ReconfigWatcher {
    private var handler: (() -> Void)?
    private var pending: DispatchWorkItem?
    private let delay: TimeInterval

    public init(delay: TimeInterval = 0.5) { self.delay = delay }

    public func start(_ handler: @escaping () -> Void) {
        self.handler = handler
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            // begin 단계는 건너뛰고 완료 후에만 처리한다.
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let me = Unmanaged<ReconfigWatcher>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { me.schedule() }
        }, ptr)
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handler?() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
