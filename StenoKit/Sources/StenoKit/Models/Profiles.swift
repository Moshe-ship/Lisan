import Foundation

// MARK: - Language Mode

/// Primary dictation language. Used as a hint to the transcription engine.
public enum LanguageMode: String, Sendable, Codable, Equatable, CaseIterable {
    case en = "en"
    case ar = "ar"
    case auto = "auto"

    public var displayName: String {
        switch self {
        case .en:    return "English"
        case .ar:    return "Arabic"
        case .auto:  return "Auto-detect"
        }
    }

    /// whisper.cpp language code: nil for auto, explicit code otherwise.
    var whisperLanguageArg: String? {
        switch self {
        case .en:   return "en"
        case .ar:   return "ar"
        case .auto: return nil
        }
    }
}

// MARK: - Style Tone

public enum StyleTone: String, Sendable, Codable, Equatable, CaseIterable {
    case natural
    case professional
    case concise
    case friendly
    case technical
}

public enum StructureMode: String, Sendable, Codable, Equatable, CaseIterable {
    case natural
    case paragraph
    case bullets
    case email
    case command
}

public enum FillerPolicy: String, Sendable, Codable, Equatable, CaseIterable {
    case minimal
    case balanced
    case aggressive
}

public enum CommandPolicy: String, Sendable, Codable, Equatable, CaseIterable {
    case passthrough
    case transform
}

public struct StyleProfile: Sendable, Codable, Equatable {
    public var name: String
    public var tone: StyleTone
    public var structureMode: StructureMode
    public var fillerPolicy: FillerPolicy
    public var commandPolicy: CommandPolicy

    public init(
        name: String,
        tone: StyleTone,
        structureMode: StructureMode,
        fillerPolicy: FillerPolicy,
        commandPolicy: CommandPolicy
    ) {
        self.name = name
        self.tone = tone
        self.structureMode = structureMode
        self.fillerPolicy = fillerPolicy
        self.commandPolicy = commandPolicy
    }
}

public enum Scope: Sendable, Codable, Equatable {
    case global
    case app(bundleID: String)
}

public struct LexiconEntry: Sendable, Codable, Equatable {
    public var term: String
    public var preferred: String
    public var scope: Scope

    public init(term: String, preferred: String, scope: Scope) {
        self.term = term
        self.preferred = preferred
        self.scope = scope
    }
}

public struct PersonalLexicon: Sendable, Codable, Equatable {
    public var entries: [LexiconEntry]

    /// Entries are sorted longest-term-first so longer multi-word phrases
    /// match before shorter substrings during lexicon application.
    public init(entries: [LexiconEntry] = []) {
        self.entries = entries.sorted { $0.term.count > $1.term.count }
    }
}

public struct Snippet: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var trigger: String
    public var expansion: String
    public var scope: Scope

    public init(id: UUID = UUID(), trigger: String, expansion: String, scope: Scope = .global) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.scope = scope
    }
}
