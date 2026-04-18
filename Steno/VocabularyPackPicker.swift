import SwiftUI
import StenoKit

/// One-click picker for the vocabulary packs Lisan ships in its bundle.
/// Resolves the packs directory (preferring the app bundle's Resources,
/// falling back to the repo's packs/ during development), lists available
/// .txt packs with short descriptions, and sets `vocabularyFilePath` to
/// the whole directory when any pack is used — whisper's engine already
/// loads all .txt files in a directory when pointed at one.
struct VocabularyPackPicker: View {
    @Binding var preferences: AppPreferences

    private struct Pack: Identifiable {
        let id: String
        let displayName: String
        let summary: String
        let filename: String
    }

    private static let catalog: [Pack] = [
        Pack(id: "msa-business", displayName: "MSA Business",
             summary: "Modern Standard Arabic business & office terms.",
             filename: "msa-business.txt"),
        Pack(id: "khaleeji-common", displayName: "Khaleeji (Gulf)",
             summary: "Gulf dialect everyday vocabulary.",
             filename: "khaleeji-common.txt"),
        Pack(id: "shami-common", displayName: "Shami (Levantine)",
             summary: "Syrian / Lebanese / Palestinian / Jordanian dialect.",
             filename: "shami-common.txt"),
        Pack(id: "saudi-places", displayName: "Saudi Places",
             summary: "Saudi cities, regions, districts, landmarks.",
             filename: "saudi-places.txt"),
        Pack(id: "saudi-government", displayName: "Saudi Government",
             summary: "Absher, Tawakkalna, ZATCA, SDAIA, ministries.",
             filename: "saudi-government.txt"),
        Pack(id: "gcc-brands", displayName: "GCC Brands",
             summary: "Common GCC brand & company names.",
             filename: "gcc-brands.txt"),
        Pack(id: "agency-bilingual", displayName: "Agency Bilingual",
             summary: "Marketing, ads, SEO, client-facing vocabulary.",
             filename: "agency-bilingual.txt"),
        Pack(id: "medical-arabic", displayName: "Medical Arabic",
             summary: "Specialties, conditions, procedures, medications.",
             filename: "medical-arabic.txt"),
        Pack(id: "tech-bilingual", displayName: "Tech Bilingual",
             summary: "Kubernetes, GraphQL, LLM / embedding / tokenizer.",
             filename: "tech-bilingual.txt"),
        Pack(id: "islamic-terms", displayName: "Islamic Terms",
             summary: "Greetings, prayer times, surah names, phrases.",
             filename: "islamic-terms.txt")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: StenoDesign.sm) {
            HStack(alignment: .firstTextBaseline, spacing: StenoDesign.xs) {
                Text("Vocabulary packs")
                    .font(StenoDesign.bodyEmphasis())
                Spacer()
                if let dir = resolvedPacksDirectory() {
                    if isDirectoryInUse(dir) {
                        Button("Remove all") { clearVocabulary() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else {
                        Button("Use all packs") { usePacksDirectory(dir) }
                            .buttonStyle(.borderedProminent)
                            .tint(StenoDesign.accent)
                            .controlSize(.small)
                    }
                }
            }

            Text("Ship-in vocabulary bundles that bias recognition toward the terms you use most. Enable dialect packs here; the engine loads every .txt file in the packs directory.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let dir = resolvedPacksDirectory() {
                let available = availablePackFilenames(in: dir)
                ForEach(Self.catalog.filter { available.contains($0.filename) }) { pack in
                    HStack(alignment: .top, spacing: StenoDesign.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.displayName)
                                .font(StenoDesign.body())
                            Text(pack.summary)
                                .font(StenoDesign.caption())
                                .foregroundStyle(StenoDesign.textSecondary)
                        }
                        Spacer()
                        Button("Use only this") {
                            preferences.dictation.vocabularyFilePath =
                                dir.appendingPathComponent(pack.filename).path
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack(spacing: StenoDesign.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.warning)
                    Text("Bundled packs not found. Point the vocabulary path at your own packs/ directory in the Advanced field below.")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.warning)
                }
            }
        }
    }

    private func resolvedPacksDirectory() -> URL? {
        if let bundled = Bundle.main.url(forResource: "packs", withExtension: nil) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: bundled.path, isDirectory: &isDir),
               isDir.boolValue {
                return bundled
            }
        }
        // Dev fallback: when running from Xcode build output, packs folder
        // lives next to the repo root.
        let devCandidates = [
            URL(fileURLWithPath: "/Users/mousaabumazin/Projects/Lisan-local/packs", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects/Lisan/packs", isDirectory: true)
        ]
        for candidate in devCandidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    private func availablePackFilenames(in directory: URL) -> Set<String> {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(files.filter { $0.hasSuffix(".txt") })
    }

    private func isDirectoryInUse(_ directory: URL) -> Bool {
        let configured = preferences.dictation.vocabularyFilePath
        guard !configured.isEmpty else { return false }
        let configuredNormalized = (configured as NSString).standardizingPath
        let dirNormalized = (directory.path as NSString).standardizingPath
        return configuredNormalized == dirNormalized
    }

    private func usePacksDirectory(_ directory: URL) {
        preferences.dictation.vocabularyFilePath = directory.path
    }

    private func clearVocabulary() {
        preferences.dictation.vocabularyFilePath = ""
    }
}
