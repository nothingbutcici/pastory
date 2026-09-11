import AppKit
import Foundation

/// Calendar-day retention, stateless and idempotent.
///
/// Rule: pick a cleanup hour X (default 04:00) and a retention of N days. Whenever `sweep` runs:
///   - if today's X has passed, "yesterday and earlier" (for N = 1) is expired; today's items are never touched;
///   - if today's X has not come yet, only "the day before yesterday and earlier" is expired.
/// N = 3 shifts the line back two more days. Pinned items are never expired by this code.
/// Running it once or a hundred times gives the same result, so it needs no "already cleaned" flag.
/// It runs at launch, at the next X (a self re-arming timer), and every time the shelf opens.
enum Retention {
    private static var timer: Timer?

    /// First calendar day that is still kept, for `now`.
    static func keepFromDay(now: Date, cleanupHour: Int, retentionDays: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let todaysCleanup = calendar.date(bySettingHour: cleanupHour, minute: 0, second: 0, of: today) ?? today
        // Before today's cleanup time, yesterday still counts as "current".
        let cutoff = now >= todaysCleanup ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        return calendar.date(byAdding: .day, value: -(max(1, retentionDays) - 1), to: cutoff)!
    }

    static func isExpired(_ item: ClipItem, now: Date, cleanupHour: Int, retentionDays: Int, calendar: Calendar = .current) -> Bool {
        guard !item.pinned else { return false }        // Pin = keep, always
        let day = calendar.startOfDay(for: item.createdAt)
        return day < keepFromDay(now: now, cleanupHour: cleanupHour, retentionDays: retentionDays, calendar: calendar)
    }

    @MainActor
    static func sweep(now: Date = Date()) {
        let p = Preferences.shared
        let hour = p.cleanupHour, days = p.retentionDays
        ClipStore.shared.removeAll { isExpired($0, now: now, cleanupHour: hour, retentionDays: days) }
    }

    /// Launch: sweep now and arm the timer for the next cleanup time.
    @MainActor
    static func schedule() {
        sweep()
        armTimer()
    }

    /// Call after the cleanup hour changes in settings.
    @MainActor
    static func reschedule() { armTimer() }

    @MainActor
    private static func armTimer() {
        timer?.invalidate()
        let hour = Preferences.shared.cleanupHour
        guard let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: hour, minute: 0, second: 5),
                                                   matchingPolicy: .nextTime) else { return }
        // A timer that was due during sleep fires as soon as the Mac wakes, so sleep needs no special case.
        let t = Timer(fire: next, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                sweep()
                armTimer()          // and again tomorrow
            }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
