import Foundation

/// Non-secret, persisted configuration. The password lives in the Keychain,
/// everything else lives in UserDefaults.
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

    /// The account name used for the Keychain password entry. It is derived
    /// from user@host so different relays keep different saved passwords.
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

    // Password lives in the Keychain
    func savedPassword() -> String? {
        Keychain.get(account: keychainAccount)
    }

    func savePassword(_ value: String) {
        if value.isEmpty {
            Keychain.delete(account: keychainAccount)
        } else {
            Keychain.set(value, account: keychainAccount)
        }
    }

    func hasSavedPassword() -> Bool {
        Keychain.exists(account: keychainAccount)
    }
}
