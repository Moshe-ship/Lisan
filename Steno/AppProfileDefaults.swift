import Foundation
import StenoKit

/// Curated per-app defaults seeded on first run. The idea: Lisan should
/// feel designed out of the box, not generic. Each bundle ID below has a
/// StyleProfile that matches how people typically use that app:
///
/// - Terminals & IDEs → passthrough (dictated text goes through the
///   cleanup pipeline untouched; `/command` lines stay `/command`).
/// - Notes / long-form writing → paragraph structure, balanced filler
///   removal.
/// - Messaging / chat → concise sentences, aggressive filler removal.
/// - LLM chat clients (Claude / Codex / ChatGPT) → passthrough, so
///   prompts to the model aren't rewritten by our cleanup layer.
///
/// Users can always override any of these in Settings. The seed exists
/// so that the defaults match the app's purpose without the user having
/// to configure every client by hand.
enum AppProfileDefaults {
    static func seedIfEmpty(_ profiles: inout [String: StyleProfile]) {
        for (bundleID, profile) in catalog where profiles[bundleID] == nil {
            profiles[bundleID] = profile
        }
    }

    /// The full default catalog, keyed by bundle identifier.
    private static var catalog: [String: StyleProfile] {
        [
            // Terminals & shells — we do not want cleanup rewriting
            // commands dictated into a shell prompt.
            "com.apple.Terminal":          passthroughProfile("Terminal"),
            "com.googlecode.iterm2":       passthroughProfile("iTerm"),
            "dev.warp.Warp-Stable":        passthroughProfile("Warp"),
            "co.zeit.hyper":               passthroughProfile("Hyper"),

            // Code editors & IDEs
            "com.microsoft.VSCode":        passthroughProfile("VS Code"),
            "dev.zed.Zed":                 passthroughProfile("Zed"),
            "com.apple.dt.Xcode":          passthroughProfile("Xcode"),
            "com.jetbrains.intellij":      passthroughProfile("IntelliJ"),
            "com.jetbrains.WebStorm":      passthroughProfile("WebStorm"),
            "com.jetbrains.pycharm":       passthroughProfile("PyCharm"),

            // LLM chat clients — don't want our cleanup layer to rewrite
            // prompts destined for another model.
            "com.anthropic.claudefordesktop": passthroughProfile("Claude"),
            "com.openai.chat":              passthroughProfile("ChatGPT"),
            "com.openai.codex":             passthroughProfile("Codex"),

            // Long-form writing surfaces — paragraph structure, balanced
            // filler cleanup, natural tone.
            "com.apple.Notes":              longFormProfile("Notes"),
            "com.apple.TextEdit":           longFormProfile("TextEdit"),
            "com.ulyssesapp.mac":           longFormProfile("Ulysses"),
            "com.bloombuilt.dayone-mac":    longFormProfile("Day One"),
            "md.obsidian":                  longFormProfile("Obsidian"),
            "com.bear-writer":               longFormProfile("Bear"),

            // Messaging / chat — concise sentences, aggressive filler
            // removal because chat messages are short by habit.
            "com.apple.MobileSMS":          chatProfile("Messages"),
            "net.whatsapp.WhatsApp":        chatProfile("WhatsApp"),
            "org.telegram.desktop":         chatProfile("Telegram"),
            "ru.keepcoder.Telegram":        chatProfile("Telegram"),
            "com.tinyspeck.slackmacgap":    chatProfile("Slack"),
            "com.hnc.Discord":              chatProfile("Discord"),

            // Email — balanced, paragraph form.
            "com.apple.mail":               longFormProfile("Mail"),
            "com.microsoft.Outlook":        longFormProfile("Outlook"),
            "com.google.Chrome":            longFormProfile("Browser"), // safe default when no more specific match
            "com.apple.Safari":             longFormProfile("Safari")
        ]
    }

    private static func passthroughProfile(_ name: String) -> StyleProfile {
        StyleProfile(
            name: "\(name) — passthrough",
            tone: .natural,
            structureMode: .natural,
            fillerPolicy: .minimal,
            commandPolicy: .passthrough
        )
    }

    private static func longFormProfile(_ name: String) -> StyleProfile {
        StyleProfile(
            name: "\(name) — long-form",
            tone: .natural,
            structureMode: .paragraph,
            fillerPolicy: .balanced,
            commandPolicy: .transform
        )
    }

    private static func chatProfile(_ name: String) -> StyleProfile {
        StyleProfile(
            name: "\(name) — chat",
            tone: .friendly,
            structureMode: .natural,
            fillerPolicy: .aggressive,
            commandPolicy: .transform
        )
    }
}
