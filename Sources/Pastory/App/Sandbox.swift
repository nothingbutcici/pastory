import Foundation

/// Test sandbox switches. They exist only for `--selftest` runs: a normal launch ignores the environment
/// entirely, so a stray PASTORY_STORE / PASTORY_LANG in the launching shell can never redirect the app
/// away from the user's real history and settings.
enum Sandbox {
    static let isSelfTest = CommandLine.arguments.contains("--selftest")
    static let store: String? = {
        guard isSelfTest, let v = ProcessInfo.processInfo.environment["PASTORY_STORE"], !v.isEmpty else { return nil }
        return v
    }()
    static let language: String? = isSelfTest ? ProcessInfo.processInfo.environment["PASTORY_LANG"] : nil
}
