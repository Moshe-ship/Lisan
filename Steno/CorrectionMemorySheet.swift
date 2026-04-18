import SwiftUI
import StenoKit

/// Promotes corrections from a real transcript into the personal lexicon.
/// User edits the transcribed text into what it should have been; we diff
/// and propose per-word substitutions the user can opt in to save. Each
/// saved correction becomes a `LexiconEntry` that biases future cleanup.
///
/// This is the "learn my brand names / client names / Arabic names"
/// workflow — much higher leverage than chasing tiny STT gains.
struct CorrectionMemorySheet: View {
    let entry: TranscriptEntry
    let onDismiss: () -> Void

    @EnvironmentObject private var controller: DictationController
    @State private var correctedText: String
    @State private var proposedCorrections: [ProposedCorrection] = []
    @State private var recomputeTask: Task<Void, Never>?

    init(entry: TranscriptEntry, onDismiss: @escaping () -> Void) {
        self.entry = entry
        self.onDismiss = onDismiss
        _correctedText = State(initialValue: entry.cleanText.isEmpty ? entry.rawText : entry.cleanText)
    }

    private struct ProposedCorrection: Identifiable, Equatable {
        let id = UUID()
        let original: String
        let replacement: String
        var save: Bool
        var scope: CorrectionScope
    }

    private enum CorrectionScope: String, CaseIterable {
        case global = "Everywhere"
        case appSpecific = "Only in this app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StenoDesign.md) {
            header

            Divider()

            transcribedRow
            correctedEditor

            if !proposedCorrections.isEmpty {
                Divider()
                Text("Proposed lexicon entries")
                    .font(StenoDesign.bodyEmphasis())
                Text("These will bias future cleanup — select which to save.")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)

                ForEach($proposedCorrections) { $proposal in
                    correctionRow($proposal)
                }
            } else if correctedText != displayedOriginal {
                Text("Looking for substitutions…")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            } else {
                Text("Edit the corrected text above to propose lexicon entries.")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(StenoDesign.lg)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 440, idealHeight: 520)
        .modifier(OnCorrectedTextChange(text: correctedText, action: scheduleRecompute))
        .onDisappear {
            recomputeTask?.cancel()
        }
    }

    private struct OnCorrectedTextChange: ViewModifier {
        let text: String
        let action: () -> Void

        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.onChange(of: text) { _, _ in action() }
            } else {
                content.onChange(of: text) { _ in action() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Correct this transcript")
                .font(StenoDesign.heading2())
            Text("Edit the text to what Lisan should have typed. Any word substitutions you make become candidate lexicon entries so the same mistake self-corrects next time.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayedOriginal: String {
        entry.cleanText.isEmpty ? entry.rawText : entry.cleanText
    }

    private var transcribedRow: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Transcribed")
                .font(StenoDesign.captionEmphasis())
                .foregroundStyle(StenoDesign.textSecondary)
            Text(displayedOriginal)
                .font(StenoDesign.body())
                .foregroundStyle(StenoDesign.textPrimary)
                .padding(StenoDesign.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StenoDesign.surface)
                .cornerRadius(StenoDesign.radiusSmall)
                .textSelection(.enabled)
        }
    }

    private var correctedEditor: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Corrected")
                .font(StenoDesign.captionEmphasis())
                .foregroundStyle(StenoDesign.textSecondary)
            TextEditor(text: $correctedText)
                .font(StenoDesign.body())
                .frame(minHeight: 80)
                .padding(StenoDesign.xs)
                .background(StenoDesign.surface)
                .cornerRadius(StenoDesign.radiusSmall)
        }
    }

    @ViewBuilder
    private func correctionRow(_ proposal: Binding<ProposedCorrection>) -> some View {
        HStack(spacing: StenoDesign.sm) {
            Toggle("", isOn: proposal.save)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: StenoDesign.xs) {
                    Text(proposal.wrappedValue.original)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(StenoDesign.textSecondary)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                    Text(proposal.wrappedValue.replacement)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(StenoDesign.accent)
                }
                Picker("Scope", selection: proposal.scope) {
                    ForEach(CorrectionScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            let selectedCount = proposedCorrections.filter { $0.save }.count
            if selectedCount > 0 {
                Text("\(selectedCount) correction\(selectedCount == 1 ? "" : "s") will be saved")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
            }
            Spacer()
            Button("Cancel", action: onDismiss)
                .buttonStyle(.bordered)
            Button("Save corrections") {
                saveCorrections()
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(StenoDesign.accent)
            .disabled(selectedCount == 0)
        }
    }

    private func scheduleRecompute() {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            recomputeCorrections()
        }
    }

    private func recomputeCorrections() {
        let originalTokens = tokenize(displayedOriginal)
        let correctedTokens = tokenize(correctedText)
        let substitutions = alignSubstitutions(from: originalTokens, to: correctedTokens)

        // Preserve user's existing save/scope selections on overlapping entries
        // so edits don't clobber their choices. Match by (original, replacement).
        let previousByKey = Dictionary(uniqueKeysWithValues:
            proposedCorrections.map { (key: "\($0.original)||\($0.replacement)", value: $0) }
        )
        proposedCorrections = substitutions.map { sub in
            let key = "\(sub.from)||\(sub.to)"
            if let existing = previousByKey[key] {
                return existing
            }
            return ProposedCorrection(
                original: sub.from,
                replacement: sub.to,
                save: true,
                scope: .global
            )
        }
    }

    private func saveCorrections() {
        let scopeBundleID = entry.appBundleID ?? ""
        for proposal in proposedCorrections where proposal.save {
            let scope: Scope = {
                switch proposal.scope {
                case .global: return .global
                case .appSpecific:
                    return scopeBundleID.isEmpty
                        ? .global
                        : .app(bundleID: scopeBundleID)
                }
            }()
            controller.addLexiconEntry(
                term: proposal.original,
                preferred: proposal.replacement,
                scope: scope
            )
        }
    }

    // MARK: - Token helpers

    private func tokenize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private struct Substitution: Equatable {
        let from: String
        let to: String
    }

    /// Token-level alignment producing substitution pairs. Uses a
    /// Needleman-Wunsch-style LCS table; pulls matching tokens out and
    /// emits aligned mismatches as substitutions. Skips insertions and
    /// deletions because they don't produce a clean "wrong word →
    /// right word" lexicon entry. Filters trivial edits that are
    /// already the same after lowercasing + diacritic stripping so we
    /// don't propose Arabic corrections that differ only in harakat.
    private func alignSubstitutions(from a: [String], to b: [String]) -> [Substitution] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        var subs: [Substitution] = []
        var i = n, j = m
        var pendingFrom: [String] = []
        var pendingTo: [String] = []
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                flushPending(&pendingFrom, &pendingTo, into: &subs)
                i -= 1; j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                pendingFrom.insert(a[i - 1], at: 0)
                i -= 1
            } else {
                pendingTo.insert(b[j - 1], at: 0)
                j -= 1
            }
        }
        while i > 0 { pendingFrom.insert(a[i - 1], at: 0); i -= 1 }
        while j > 0 { pendingTo.insert(b[j - 1], at: 0); j -= 1 }
        flushPending(&pendingFrom, &pendingTo, into: &subs)
        return subs.filter { !isTrivialEdit(from: $0.from, to: $0.to) }
    }

    private func flushPending(
        _ pendingFrom: inout [String],
        _ pendingTo: inout [String],
        into out: inout [Substitution]
    ) {
        let count = min(pendingFrom.count, pendingTo.count)
        for idx in 0..<count {
            out.append(.init(from: pendingFrom[idx], to: pendingTo[idx]))
        }
        pendingFrom.removeAll()
        pendingTo.removeAll()
    }

    private func isTrivialEdit(from: String, to: String) -> Bool {
        let normalize: (String) -> String = { s in
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .punctuationCharacters)
        }
        return normalize(from) == normalize(to)
    }
}
