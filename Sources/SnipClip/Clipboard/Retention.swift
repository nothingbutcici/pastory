import AppKit
import Foundation

/// Days roll over at 04:00 local time, so a late-night session counts as one day.
enum Retention {
    static let rolloverHour = 4

    static func dayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        let shifted = date.addingTimeInterval(-TimeInterval(rolloverHour * 3600))
        let start = calendar.startOfDay(for: shifted)
        return Int(start.timeIntervalSince1970 / 86400)
    }

    /// Drop unpinned items whose day is at least `days` days behind today.
    @MainActor
    static func sweep(now: Date = Date()) {
        let days = Preferences.shared.retentionDays
        let today = dayIndex(now)
        ClipStore.shared.removeAll { !$0.pinned && dayIndex($0.createdAt) <= today - days }
    }

    /// At launch, every hour, and right after the Mac wakes (a 04:00 rollover that happened during sleep
    /// is applied at wake, not an hour later).
    @MainActor
    static func schedule() {
        sweep()
        let t = Timer(timeInterval: 3600, repeats: true) { _ in MainActor.assumeIsolated { sweep() } }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sweep() }
        }
    }
}
