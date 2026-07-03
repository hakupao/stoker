import Combine
import Foundation

/// Free-running counter that drives the menu-bar flame flicker.
///
/// Deliberately its own `ObservableObject` rather than a `@Published` counter on the
/// shared app model: `objectWillChange` invalidates *every* view observing an object,
/// so a 0.45s tick published from the shared model re-rendered the main window's
/// entire view tree — which macOS keeps alive (offscreen) after the window closes —
/// including a Swift Charts history view, pinning a core at ~100% for as long as the
/// schedule stayed lit. Scoped here, each tick invalidates only the views that
/// observe the ticker (the `MenuBarExtra` label).
@MainActor
public final class FlameTicker: ObservableObject {
    /// Current animation frame; consumers index their frame table with `frame % count`.
    @Published public private(set) var frame = 0

    private var timer: Timer?

    public init() {}

    public var isRunning: Bool { timer != nil }

    /// Starts or stops the 0.45s tick. Idempotent. Stopping resets `frame` so the
    /// flame always relights from its first frame.
    ///
    /// `Timer.invalidate()` is only valid on the thread that installed the timer
    /// (the main run loop here) — `@MainActor` guarantees both ends. The owner is
    /// expected to live for the app's lifetime, so there is no teardown in `deinit`;
    /// the only uncovered case is process exit.
    public func setRunning(_ running: Bool) {
        if running {
            guard timer == nil else { return }
            // The increment must be synchronous (assumeIsolated, not a Task hop):
            // a hop enqueued right before setRunning(false) would land *after* the
            // frame = 0 reset and bump a stopped ticker back to frame 1. The timer
            // lives on the main run loop, so the callback is always on the main
            // thread and assumeIsolated cannot trap.
            let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.frame &+= 1 }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            frame = 0
        }
    }
}
