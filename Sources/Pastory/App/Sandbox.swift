import Foundation

/// Test sandbox switches. They exist only for `--selftest` runs: a normal launch ignores the environment
/// entirely, so a stray PASTORY_STORE / PASTORY_LANG in the launching shell can never redirect the app
/// away from the user's real history and settings.
enum Sandbox {
    static let isSelfTest: Bool = {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--selftest") else { return false }
        return i + 1 < a.count                      // a bare --selftest is a normal launch
    }()
    static let store: String? = {
        guard isSelfTest, let v = ProcessInfo.processInfo.environment["PASTORY_STORE"], !v.isEmpty else { return nil }
        return v
    }()
    static let language: String? = isSelfTest ? ProcessInfo.processInfo.environment["PASTORY_LANG"] : nil
}
