import AppKit
import Foundation

/// Calendar-day retention, stateless and idempotent.
///
/// Rule: pick a cleanup hour X (default 04:00) and a retention of N days. Whenever `sweep` runs:
///   - if today's X has passed, "yesterday and earlier" (for N = 1) is expired; today's items are never touched;
///   - if today's X has not come yet, only "the day before yesterday and earlier" is expired.
/// N = 3 shifts the line back two more days. Pinned items are never expired by this code.
/// Running it once or a hundred times gives the same result, so it needs no "already cleaned" flag.
/// N = 0 means never: nothing expires and no timer is armed.
/// It runs at launch and from one timer set to the moment the oldest unpinned item expires
/// (its day + N days, at X) — so with N = 7 the timer sleeps for days, not once per day.
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
        guard retentionDays > 0 else { return false }   // never clean up
        let day = calendar.startOfDay(for: item.createdAt)
        return day < keepFromDay(now: now, cleanupHour: cleanupHour, retentionDays: retentionDays, calendar: calendar)
    }

    @MainActor
    static func sweep(now: Date = Date()) {
        guard !ClipStore.shared.lastSaveFailed else { return }      // never delete files when the index cannot be written
        let p = Preferences.shared
        guard !p.neverCleans else { return }
        let hour = p.cleanupHour, days = p.retentionDays
        ClipStore.shared.removeAll { isExpired($0, now: now, cleanupHour: hour, retentionDays: days) }
    }

    /// The instant an item created on `day` stops being kept: (day + N days) at hour X.
    static func expiryMoment(of item: ClipItem, cleanupHour: Int, retentionDays: Int, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: item.createdAt)
        guard let d = calendar.date(byAdding: .day, value: max(1, retentionDays), to: day) else { return nil }
        return calendar.date(bySettingHour: cleanupHour, minute: 0, second: 5, of: d)
    }

    /// Launch: sweep now and arm the timer.
    @MainActor
    static func schedule() {
        sweep()
        armTimer()
    }

    /// After the cleanup hour or retention days change, or after a sweep.
    @MainActor
    static func reschedule() { armTimer() }

    /// A new item arrived; if nothing was scheduled (store was empty), schedule for it.
    @MainActor
    static func itemAdded() { if timer == nil { armTimer() } }

    @MainActor
    private static func armTimer() {
        timer?.invalidate()
        timer = nil
        let p = Preferences.shared
        let hour = p.cleanupHour, days = p.retentionDays
        guard days > 0 else { return }                              // never: no timer at all
        guard !ClipStore.shared.lastSaveFailed else { return }      // re-armed by the store once a save succeeds
        // Earliest expiry among unpinned items; nothing unpinned → nothing to schedule.
        let moments = ClipStore.shared.items.filter { !$0.pinned }.compactMap { expiryMoment(of: $0, cleanupHour: hour, retentionDays: days) }
        guard let earliest = moments.min() else { return }
        let fire = max(earliest, Date().addingTimeInterval(5))
        // A timer that was due during sleep fires as soon as the Mac wakes, so sleep needs no special case.
        let t = Timer(fire: fire, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                sweep()
                armTimer()          // next-oldest item, whenever that is
            }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Self-test / diagnostics: when the current timer will fire.
    @MainActor
    static var nextFire: Date? { timer?.fireDate }
}
