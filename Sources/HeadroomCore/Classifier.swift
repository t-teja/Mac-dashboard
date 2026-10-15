import Foundation

public struct CleanupRule: Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let tier: SafetyTier
    public let category: DiskCategory
    public let match: RuleMatch

    public init(id: String, title: String, detail: String, tier: SafetyTier, category: DiskCategory, match: RuleMatch) {
        self.id = id
        self.title = title
        self.detail = detail
        self.tier = tier
        self.category = category
        self.match = match
    }
}

public enum RuleMatch: Sendable, Equatable {
    case homePrefix(String)
    case lastComponent(String)
    case pathContains(String)
}

public enum Classifier {
    public static let rules: [CleanupRule] = [
        CleanupRule(id: "xcode.derived", title: "Xcode DerivedData", detail: "Build products and indexes. The next build recreates them.", tier: .safe, category: .developerTools, match: .homePrefix("Library/Developer/Xcode/DerivedData")),
        CleanupRule(id: "xcode.cache", title: "Xcode caches", detail: "Module and preview caches Xcode rebuilds as it needs them.", tier: .safe, category: .developerTools, match: .homePrefix("Library/Caches/com.apple.dt.Xcode")),
        CleanupRule(id: "sim.caches", title: "Simulator caches", detail: "CoreSimulator's regenerable cache. Skipped while a simulator is in use is your call.", tier: .safe, category: .mobileSDKs, match: .homePrefix("Library/Developer/CoreSimulator/Caches")),
        CleanupRule(id: "homebrew.cache", title: "Homebrew downloads", detail: "Old bottles. Brew downloads them again if a formula needs them.", tier: .safe, category: .packageCaches, match: .homePrefix("Library/Caches/Homebrew")),
        CleanupRule(id: "npm.cache", title: "npm cache", detail: "The global npm cache.", tier: .safe, category: .packageCaches, match: .homePrefix(".npm")),
        CleanupRule(id: "pnpm.store", title: "pnpm store", detail: "pnpm's content-addressed store.", tier: .safe, category: .packageCaches, match: .homePrefix("Library/pnpm")),
        CleanupRule(id: "yarn.cache", title: "Yarn cache", detail: "Yarn's download cache.", tier: .safe, category: .packageCaches, match: .homePrefix("Library/Caches/Yarn")),
        CleanupRule(id: "yarn.cache.home", title: "Yarn cache", detail: "Yarn's download cache.", tier: .safe, category: .packageCaches, match: .homePrefix(".cache/yarn")),
        CleanupRule(id: "gradle.caches", title: "Gradle caches", detail: "Gradle will redownload what the next build needs.", tier: .safe, category: .packageCaches, match: .homePrefix(".gradle/caches")),
        CleanupRule(id: "pip.cache", title: "pip cache", detail: "Python wheels pip can fetch again.", tier: .safe, category: .packageCaches, match: .homePrefix("Library/Caches/pip")),
        CleanupRule(id: "uv.cache", title: "uv cache", detail: "The uv package cache.", tier: .safe, category: .packageCaches, match: .homePrefix(".cache/uv")),
        CleanupRule(id: "puppeteer.cache", title: "Puppeteer cache", detail: "Downloaded browsers Puppeteer can fetch again.", tier: .safe, category: .packageCaches, match: .homePrefix(".cache/puppeteer")),
        CleanupRule(id: "swiftpm.cache", title: "Swift package cache", detail: "SourceKit and SwiftPM caches.", tier: .safe, category: .packageCaches, match: .homePrefix("Library/Caches/org.swift.swiftpm")),
        CleanupRule(id: "cargo.registry", title: "Cargo registry", detail: "Downloaded crates. Cargo fetches them again.", tier: .safe, category: .packageCaches, match: .homePrefix(".cargo/registry")),
        CleanupRule(id: "xcode.devicesupport", title: "iOS DeviceSupport", detail: "Symbol files copied from phones you have plugged in. Xcode copies them again next time.", tier: .review, category: .mobileSDKs, match: .homePrefix("Library/Developer/Xcode/iOS DeviceSupport")),
        CleanupRule(id: "xcode.devicesupport", title: "watchOS DeviceSupport", detail: "Symbol files for watches. Xcode copies them again next time.", tier: .review, category: .mobileSDKs, match: .homePrefix("Library/Developer/Xcode/watchOS DeviceSupport")),
        CleanupRule(id: "xcode.devicesupport", title: "tvOS DeviceSupport", detail: "Symbol files for Apple TV. Xcode copies them again next time.", tier: .review, category: .mobileSDKs, match: .homePrefix("Library/Developer/Xcode/tvOS DeviceSupport")),
        CleanupRule(id: "xcode.archives", title: "Xcode archives", detail: "Old release archives. Keep the ones you still ship.", tier: .review, category: .developerTools, match: .homePrefix("Library/Developer/Xcode/Archives")),
        CleanupRule(id: "user.logs", title: "User logs", detail: "Logs under ~/Library/Logs. Apps write new ones.", tier: .review, category: .developerTools, match: .homePrefix("Library/Logs")),
        CleanupRule(id: "android.images", title: "Android system images", detail: "Emulator OS images. Android Studio can download them again.", tier: .review, category: .osImages, match: .homePrefix("Library/Android/sdk/system-images")),
        CleanupRule(id: "android.sdk", title: "Android SDK", detail: "The SDK, including images and platforms. Android Studio will redownload what it needs.", tier: .review, category: .mobileSDKs, match: .homePrefix("Library/Android")),
        CleanupRule(id: "android.home", title: "Android home", detail: "AVDs and Android caches in ~/.android.", tier: .review, category: .mobileSDKs, match: .homePrefix(".android")),
        CleanupRule(id: "ollama", title: "Ollama models", detail: "Local models. Pull them again if you still want them.", tier: .review, category: .aiModels, match: .homePrefix(".ollama")),
        CleanupRule(id: "ollama.support", title: "Ollama support", detail: "Ollama's application support folder.", tier: .review, category: .aiModels, match: .homePrefix("Library/Application Support/Ollama")),
        CleanupRule(id: "huggingface", title: "Hugging Face cache", detail: "Downloaded model weights.", tier: .review, category: .aiModels, match: .homePrefix(".cache/huggingface")),
        CleanupRule(id: "huggingface", title: "Hugging Face cache", detail: "Downloaded model weights.", tier: .review, category: .aiModels, match: .homePrefix("Library/Caches/huggingface")),
        CleanupRule(id: "lmstudio", title: "LM Studio models", detail: "May include settings as well as weights.", tier: .review, category: .aiModels, match: .homePrefix("Library/Application Support/LM Studio")),
        CleanupRule(id: "lmstudio", title: "LM Studio models", detail: "Local LM Studio data.", tier: .review, category: .aiModels, match: .homePrefix(".lmstudio")),
        CleanupRule(id: "node.modules", title: "node_modules", detail: "Dependencies. Your package manager can reinstall them.", tier: .review, category: .packageCaches, match: .lastComponent("node_modules")),
        CleanupRule(id: "next.build", title: "Next.js build output", detail: "The .next folder. The next build recreates it.", tier: .review, category: .packageCaches, match: .lastComponent(".next")),
        CleanupRule(id: "turbo.cache", title: "Turbo cache", detail: "Turborepo's local cache.", tier: .review, category: .packageCaches, match: .lastComponent(".turbo")),
        CleanupRule(id: "swift.build", title: "Swift build folder", detail: "The .build directory. SwiftPM recreates it.", tier: .review, category: .developerTools, match: .lastComponent(".build")),
        CleanupRule(id: "xcode.derived", title: "DerivedData", detail: "A DerivedData folder outside the default location.", tier: .safe, category: .developerTools, match: .lastComponent("DerivedData")),
        CleanupRule(id: "carthage.build", title: "Carthage build", detail: "Carthage build products. Carthage can rebuild them.", tier: .review, category: .developerTools, match: .pathContains("/Carthage/Build"))
    ]

    /// Longest home prefix wins, then a last-component rule. Protected paths never match.
    public static func rule(for path: String, home: String) -> CleanupRule? {
        let path = SecurityGate.standardized(path)
        if SecurityGate.denyReason(path) != nil { return nil }
        if let relative = SecurityGate.relativeToHome(path, home: home) {
            var best: (CleanupRule, Int)?
            for rule in rules {
                if case .homePrefix(let prefix) = rule.match, matchesPrefix(relative, prefix) {
                    if best == nil || prefix.count > best!.1 {
                        best = (rule, prefix.count)
                    }
                }
            }
            if let best { return best.0 }
        }
        return componentRule(path)
    }

    public static func category(for path: String, home: String) -> DiskCategory {
        let path = SecurityGate.standardized(path)
        let lower = path.lowercased()
        if lower.contains("/.ollama") || lower.contains("huggingface") || lower.contains("lm studio") || lower.contains("/.lmstudio") {
            return .aiModels
        }
        if lower.contains("system-images") || lower.hasSuffix(".ipsw") || lower.contains("install macos") {
            return .osImages
        }
        if lower.contains("/android") || lower.contains("coresimulator") || lower.contains("devicesupport") {
            return .mobileSDKs
        }
        if lower.contains("node_modules") || lower.contains("/.npm") || lower.contains("/.gradle")
            || lower.contains("/.cargo") || lower.contains("/caches/") || lower.contains("/.cache/") {
            return .packageCaches
        }
        if lower.contains("deriveddata") || lower.contains("/xcode") || lower.hasSuffix("/.build") {
            return .developerTools
        }
        if let relative = SecurityGate.relativeToHome(path, home: home) {
            let top = relative.split(separator: "/").first.map(String.init) ?? ""
            if ["Documents", "Desktop", "Pictures", "Movies", "Music"].contains(top) { return .documentsMedia }
            if ["Developer", "Projects", "Code", "src", "dev"].contains(top) { return .codeProjects }
        }
        if lower.contains("/documents/") || lower.contains("/desktop/") || lower.contains("/pictures/") {
            return .documentsMedia
        }
        return .systemOther
    }

    private static func componentRule(_ path: String) -> CleanupRule? {
        if path.contains("/Carthage/Build") {
            return rules.first { $0.id == "carthage.build" }
        }
        let last = (path as NSString).lastPathComponent
        return rules.first { rule in
            if case .lastComponent(let name) = rule.match { return name == last }
            return false
        }
    }

    private static func matchesPrefix(_ relative: String, _ prefix: String) -> Bool {
        relative == prefix || relative.hasPrefix(prefix + "/")
    }
}
