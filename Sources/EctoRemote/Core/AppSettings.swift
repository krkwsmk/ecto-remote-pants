import Foundation

/// Persisted configuration stored in UserDefaults, including the relay
/// password (base64-encoded; obfuscation, not encryption).
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Keys
    private enum Key {
        static let sshUser = "ssh.user"
        static let sshHost = "ssh.host"
        static let sshExtraArgs = "ssh.extraArgs"
        static let ncatTemplate = "ncat.template"
        static let lastPort = "last.port"
        static let keychainAccount = "keychain.account"
        static let autoStartListener = "auto.startListener"
    }

    /// Account name used to scope the saved password. Derived from user@host
    /// so different relays keep different saved passwords.
    var keychainAccount: String {
        "\(sshUser)@\(sshHost)"
    }

    var sshUser: String {
        get { defaults.string(forKey: Key.sshUser) ?? "debug" }
        set { defaults.set(newValue, forKey: Key.sshUser) }
    }

    var sshHost: String {
        get { defaults.string(forKey: Key.sshHost) ?? "176.53.160.131" }
        set { defaults.set(newValue, forKey: Key.sshHost) }
    }

    /// Extra arguments appended to the ssh invocation (advanced use).
    var sshExtraArgs: String {
        get { defaults.string(forKey: Key.sshExtraArgs) ?? "" }
        set { defaults.set(newValue, forKey: Key.sshExtraArgs) }
    }

    /// Command template for the listener. `{PORT}` is substituted at runtime.
    var ncatTemplate: String {
        get { defaults.string(forKey: Key.ncatTemplate) ?? "ncat -lvkp {PORT}" }
        set { defaults.set(newValue, forKey: Key.ncatTemplate) }
    }

    var lastPort: String {
        get { defaults.string(forKey: Key.lastPort) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastPort) }
    }

    /// When true, the listener starts automatically once the tunnel is up.
    var autoStartListener: Bool {
        get { defaults.object(forKey: Key.autoStartListener) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoStartListener) }
    }

    // Password is stored in the app's own preferences (not the macOS Keychain).
    // The Keychain triggers a login-password prompt on every launch for an
    // ad-hoc-signed app, so for this internal tool we keep it in UserDefaults,
    // base64-encoded (obfuscation, not encryption).
    private func passwordKey() -> String { "pw." + keychainAccount }

    func savedPassword() -> String? {
        guard let b64 = defaults.string(forKey: passwordKey()),
              let data = Data(base64Encoded: b64),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func savePassword(_ value: String) {
        let key = passwordKey()
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(Data(value.utf8).base64EncodedString(), forKey: key)
        }
    }

    func hasSavedPassword() -> Bool {
        !(savedPassword() ?? "").isEmpty
    }
}
