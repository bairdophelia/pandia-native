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
    /// Off by default. On: PandiaBrain never falls back to cloud after a
    /// local-model failure — it returns the actual error instead. Added
    /// because the normal fallback silently masks local failures behind a
    /// working cloud reply, which is exactly wrong for testing whether the
    /// local model itself works — see PandiaBrain.swift's doc comment.
    /// Doesn't touch the LAN check: this is specifically about not letting
    /// cloud paper over a local problem, not about refusing Selene.
    @Published var localOnlyMode: Bool {
        didSet { UserDefaults.standard.set(localOnlyMode, forKey: Self.localOnlyModeKey) }
    }
    /// Off by default — picks `pandiaLocalSystemPrompt`
    /// (PersonalityPrompt.swift) instead of the full `pandiaSystemPrompt`,
    /// matching what 2026-09-01's on-device testing found the default 1B
    /// model can actually hold onto (see LocalBrain.swift). On: feeds the
    /// same full prompt CloudBrain.swift uses to the on-device model
    /// instead — Fia's ask, worth trying deliberately once a bigger model
    /// (3B+) is actually reachable, now that LocalBrainProgress gives a
    /// real progress bar instead of a bare hourglass during the load that
    /// comes with it.
    @Published var useFullPersonalityPrompt: Bool {
        didSet { UserDefaults.standard.set(useFullPersonalityPrompt, forKey: Self.useFullPersonalityPromptKey) }
    }

    private static let lanHostKey = "lanHost"
    private static let lanTokenKey = "lanToken"
    private static let cloudProviderKey = "cloudProvider"
    private static let cloudApiKeyKey = "cloudApiKey"
    private static let requireCloudConsentKey = "requireCloudConsent"
    private static let useLocalModelKey = "useLocalModel"
    private static let localModelIdKey = "localModelId"
    private static let localOnlyModeKey = "localOnlyMode"
    private static let useFullPersonalityPromptKey = "useFullPersonalityPrompt"
    // Reverted (2026-09-01) back to Llama-3.2-1B, after the brief 3B
    // default (2026-08-28) crashed on an actual device test — almost
    // certainly memory pressure: ~1.8GB of weights alone, before MLX's
    // own runtime overhead and KV cache, is enough to get an app killed
    // by iOS on some phones. Unlike a thrown Swift error, an OS memory
    // kill can't be caught or recovered from in code — the fix has to be
    // "don't default to a model that needs more memory than the device
    // reliably has," not a try/catch. 3B stays available as a picker
    // option in SettingsView.swift for anyone on a higher-RAM phone who
    // wants to opt into that risk deliberately; it just isn't safe to
    // hand to every fresh install as the default.
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
        localOnlyMode = UserDefaults.standard.object(forKey: Self.localOnlyModeKey) as? Bool ?? false
        useFullPersonalityPrompt = UserDefaults.standard.object(forKey: Self.useFullPersonalityPromptKey) as? Bool ?? false
    }
}
