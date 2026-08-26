import Foundation

// Stage 2 added lanHost/lanToken; Stage 3 added cloud fallback's slice
// (provider, key, consent); Stage 5 adds useLocalModel/localModelId (see
// ../README.md's staged plan for why this wasn't all built at once). API
// keys sit in plain UserDefaults for now, same as the PWA's IndexedDB
// approach (never committed to the repo — see ../.gitignore); moving to
// Keychain is a reasonable later hardening step, not a blocker here.
final class PandiaSettings: ObservableObject {
    @Published var lanHost: String {
        didSet { UserDefaults.standard.set(lanHost, forKey: Self.lanHostKey) }
    }
    @Published var lanToken: String {
        didSet { UserDefaults.standard.set(lanToken, forKey: Self.lanTokenKey) }
    }
    @Published var cloudProvider: CloudProvider {
        didSet { UserDefaults.standard.set(cloudProvider.rawValue, forKey: Self.cloudProviderKey) }
    }
    @Published var cloudApiKey: String {
        didSet { UserDefaults.standard.set(cloudApiKey, forKey: Self.cloudApiKeyKey) }
    }
    @Published var requireCloudConsent: Bool {
        didSet { UserDefaults.standard.set(requireCloudConsent, forKey: Self.requireCloudConsentKey) }
    }
    /// Off by default — same reasoning as requireCloudConsent's default,
    /// just pointed the other way: turning this on kicks off a multi-
    /// hundred-MB download (see LocalBrain.swift) the first time it's
    /// used, which shouldn't happen without an explicit opt-in.
    @Published var useLocalModel: Bool {
        didSet { UserDefaults.standard.set(useLocalModel, forKey: Self.useLocalModelKey) }
    }
    /// Hugging Face repo id, mlx-community's MLX-converted format — see
    /// LocalBrain.swift's doc comment for why this specific model is the
    /// default (small enough for a phone, well-known in this ecosystem).
    @Published var localModelId: String {
        didSet { UserDefaults.standard.set(localModelId, forKey: Self.localModelIdKey) }
    }

    private static let lanHostKey = "lanHost"
    private static let lanTokenKey = "lanToken"
    private static let cloudProviderKey = "cloudProvider"
    private static let cloudApiKeyKey = "cloudApiKey"
    private static let requireCloudConsentKey = "requireCloudConsent"
    private static let useLocalModelKey = "useLocalModel"
    private static let localModelIdKey = "localModelId"
    private static let defaultLocalModelId = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    init() {
        lanHost = UserDefaults.standard.string(forKey: Self.lanHostKey) ?? ""
        lanToken = UserDefaults.standard.string(forKey: Self.lanTokenKey) ?? ""
        let providerRaw = UserDefaults.standard.string(forKey: Self.cloudProviderKey) ?? CloudProvider.anthropic.rawValue
        cloudProvider = CloudProvider(rawValue: providerRaw) ?? .anthropic
        cloudApiKey = UserDefaults.standard.string(forKey: Self.cloudApiKeyKey) ?? ""
        // Fia's explicit ask on the PWA side (2026-08-23): default ON —
        // same reasoning applies here, see CloudBrain.swift's doc comment.
        requireCloudConsent = UserDefaults.standard.object(forKey: Self.requireCloudConsentKey) as? Bool ?? true
        useLocalModel = UserDefaults.standard.object(forKey: Self.useLocalModelKey) as? Bool ?? false
        localModelId = UserDefaults.standard.string(forKey: Self.localModelIdKey) ?? Self.defaultLocalModelId
    }
}
