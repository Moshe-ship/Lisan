import SwiftUI
import StenoKit

/// Multi-select pack picker with priority ordering and visible chips for
/// enabled packs. Writes the ordered list into
/// `preferences.dictation.enabledPackFilenames` — empty array means "all
/// packs" (legacy behavior). Splits the mental model cleanly:
///
/// - **Decoder bias (whisper prompt)** — what this picker controls. Each
///   enabled pack's lines are concatenated and fed to whisper as a
///   `--prompt` string. Whisper is biased to spell these terms correctly
///   when they show up in speech, but *it is not a find/replace*. If
///   whisper never hears your term, no bias shows it.
///
/// - **Post-cleanup corrections (lexicon)** — managed separately in the
///   Word Corrections section. These are real substitutions applied
///   after transcription. They catch the misfires that decoder bias
///   alone didn't solve.
///
/// The two systems are complementary: bias first, correct second.
struct VocabularyPackPicker: View {
    @Binding var preferences: AppPreferences

    private struct Pack: Identifiable, Equatable {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary packs")
                        .font(StenoDesign.bodyEmphasis())
                    Text("Decoder bias — fed to whisper as a prompt to bias recognition")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                }
                Spacer()
                if !effectiveFilenames.isEmpty {
                    Button("Use all") { enableAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Clear all") { clearAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(preferences.dictation.enabledPackFilenames.isEmpty)
            }

            if !enabledChips.isEmpty {
                enabledChipsRow
            }

            if let dir = resolvedPacksDirectory() {
                let available = availablePackFilenames(in: dir)
                ForEach(Self.catalog.filter { available.contains($0.filename) }) { pack in
                    packRow(pack)
                }
            } else {
                HStack(spacing: StenoDesign.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.warning)
                    Text("Bundled packs not found. Add custom packs in the Advanced section below.")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.warning)
                }
            }

            Text("Tip: order matters — packs higher in your list bias the decoder more strongly. Word-level substitutions belong in the Word Corrections section below, not here.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, StenoDesign.xs)
        }
    }

    private var enabledChipsRow: some View {
        // ScrollView to keep the row height bounded even when many packs
        // are on. Each chip shows the pack name and a remove button.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StenoDesign.xs) {
                ForEach(Array(preferences.dictation.enabledPackFilenames.enumerated()), id: \.offset) { index, filename in
                    if let entry = Self.catalog.first(where: { $0.filename == filename }) {
                        chip(entry: entry, index: index)
                    } else {
                        // Custom pack filename that isn't in our catalog — still show it.
                        chip(entry: Pack(id: filename, displayName: filename, summary: "", filename: filename), index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(entry: Pack, index: Int) -> some View {
        HStack(spacing: StenoDesign.xxs) {
            Text("\(index + 1).")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(StenoDesign.textSecondary)
            Text(entry.displayName)
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.accent)
            Button {
                remove(filename: entry.filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(StenoDesign.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, StenoDesign.xs)
        .padding(.vertical, StenoDesign.xxs)
        .background(StenoDesign.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(StenoDesign.accent.opacity(0.4), lineWidth: 1))
    }

    @ViewBuilder
    private func packRow(_ pack: Pack) -> some View {
        let isEnabled = preferences.dictation.enabledPackFilenames.contains(pack.filename)
        let priorityIndex = preferences.dictation.enabledPackFilenames.firstIndex(of: pack.filename)

        HStack(alignment: .top, spacing: StenoDesign.sm) {
            Button {
                toggle(pack)
            } label: {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isEnabled ? StenoDesign.accent : StenoDesign.textSecondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: StenoDesign.xs) {
                    Text(pack.displayName)
                        .font(StenoDesign.body())
                    if let i = priorityIndex {
                        Text("priority \(i + 1)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(StenoDesign.accent)
                    }
                }
                Text(pack.summary)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            }

            Spacer()

            if isEnabled {
                HStack(spacing: 2) {
                    Button { moveUp(pack) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(priorityIndex == 0)
                    .accessibilityLabel("Raise priority")

                    Button { moveDown(pack) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(priorityIndex == preferences.dictation.enabledPackFilenames.count - 1)
                    .accessibilityLabel("Lower priority")
                }
                .foregroundStyle(StenoDesign.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var enabledChips: [String] {
        preferences.dictation.enabledPackFilenames
    }

    private var effectiveFilenames: [String] {
        if !preferences.dictation.enabledPackFilenames.isEmpty {
            return preferences.dictation.enabledPackFilenames
        }
        // Legacy "load all" state — treat as "all available".
        guard let dir = resolvedPacksDirectory() else { return [] }
        return availablePackFilenames(in: dir).sorted()
    }

    private func toggle(_ pack: Pack) {
        if let i = preferences.dictation.enabledPackFilenames.firstIndex(of: pack.filename) {
            preferences.dictation.enabledPackFilenames.remove(at: i)
        } else {
            preferences.dictation.enabledPackFilenames.append(pack.filename)
        }
        ensureVocabularyPath()
    }

    private func remove(filename: String) {
        preferences.dictation.enabledPackFilenames.removeAll { $0 == filename }
    }

    private func moveUp(_ pack: Pack) {
        guard let i = preferences.dictation.enabledPackFilenames.firstIndex(of: pack.filename), i > 0 else { return }
        preferences.dictation.enabledPackFilenames.swapAt(i, i - 1)
    }

    private func moveDown(_ pack: Pack) {
        guard let i = preferences.dictation.enabledPackFilenames.firstIndex(of: pack.filename),
              i < preferences.dictation.enabledPackFilenames.count - 1 else { return }
        preferences.dictation.enabledPackFilenames.swapAt(i, i + 1)
    }

    private func enableAll() {
        guard let dir = resolvedPacksDirectory() else { return }
        let all = availablePackFilenames(in: dir).sorted()
        preferences.dictation.enabledPackFilenames = Array(all)
        ensureVocabularyPath()
    }

    private func clearAll() {
        preferences.dictation.enabledPackFilenames = []
    }

    private func ensureVocabularyPath() {
        // If the user enables a pack, make sure vocabularyFilePath points
        // at a directory we can resolve — otherwise the engine loader has
        // nowhere to look.
        if preferences.dictation.vocabularyFilePath.isEmpty,
           let dir = resolvedPacksDirectory() {
            preferences.dictation.vocabularyFilePath = dir.path
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
        let devCandidates = [
            URL(fileURLWithPath: "/Users/mousaabumazin/Projects/Lisan-local/packs", isDirectory: true)
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
}
