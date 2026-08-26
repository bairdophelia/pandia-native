import Foundation

// Stage 2 added lanHost/lanToken; Stage 3 adds cloud fallback's slice
// (provider, key, consent). useLocalModel/localModelId still wait for
// Stage 4 (MLX) — see ../README.md's staged plan for why this isn't all
// built at once. API keys sit in plain UserDefaults for now, same as the
// PWA's IndexedDB approach (never committed to the repo — see
// ../.gitignore); moving to Keychain is a reasonable later hardening step,
// not a Stage 3 blocker.
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

    private static let lanHostKey = "lanHost"
    private static let lanTokenKey = "lanToken"
    private static let cloudProviderKey = "cloudProvider"
    private static let cloudApiKeyKey = "cloudApiKey"
    private static let requireCloudConsentKey = "requireCloudConsent"

    init() {
        lanHost = UserDefaults.standard.string(forKey: Self.lanHostKey) ?? ""
        lanToken = UserDefaults.standard.string(forKey: Self.lanTokenKey) ?? ""
        let providerRaw = UserDefaults.standard.string(forKey: Self.cloudProviderKey) ?? CloudProvider.anthropic.rawValue
        cloudProvider = CloudProvider(rawValue: providerRaw) ?? .anthropic
        cloudApiKey = UserDefaults.standard.string(forKey: Self.cloudApiKeyKey) ?? ""
        // Fia's explicit ask on the PWA side (2026-08-23): default ON —
        // same reasoning applies here, see CloudBrain.swift's doc comment.
        requireCloudConsent = UserDefaults.standard.object(forKey: Self.requireCloudConsentKey) as? Bool ?? true
    }
}
