import AppKit
import SwiftUI
import StenoKit

/// Structured private-beta feedback form. Collects the fields the
/// review checklist specified — app used, phrase said, what came out,
/// model/mode/packs, dialect, whether correction fixed it — and lets
/// the tester submit via copy-to-clipboard or mailto: (no servers).
///
/// This is opt-in per submission: nothing is auto-uploaded. Testers
/// choose what text to include in each report. Lisan pre-fills the
/// metadata (model, language mode, packs, etc.) so testers only have
/// to type the phrase and what happened.
struct BetaFeedbackSheet: View {
    @EnvironmentObject private var controller: DictationController
    let onDismiss: () -> Void

    @State private var appUsed: String = ""
    @State private var phraseSaid: String = ""
    @State private var whatCameOut: String = ""
    @State private var whatShouldHaveComeOut: String = ""
    @State private var dialect: Dialect = .notSpecified
    @State private var correctionFixedIt: CorrectionOutcome = .notTried
    @State private var notes: String = ""
    @State private var submitConfirmation: String?

    enum Dialect: String, CaseIterable, Identifiable {
        case notSpecified = "Not specified"
        case msa = "MSA / Fusha"
        case khaleeji = "Khaleeji (Gulf)"
        case shami = "Shami (Levantine)"
        case masri = "Masri (Egyptian)"
        case maghrebi = "Maghrebi (North African)"
        case iraqi = "Iraqi"
        case other = "Other"
        var id: String { rawValue }
    }

    enum CorrectionOutcome: String, CaseIterable, Identifiable {
        case notTried = "Did not try the correction flow"
        case fixed = "Yes, correction flow fixed it"
        case partial = "Partially fixed"
        case notFixed = "No, correction flow did not fix it"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StenoDesign.md) {
                header
                Divider()
                phraseBlock
                Divider()
                contextBlock
                Divider()
                notesBlock

                if let submitConfirmation {
                    Text(submitConfirmation)
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.success)
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(StenoDesign.lg)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 560, idealHeight: 680)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Beta feedback")
                .font(StenoDesign.heading2())
            Text("Lisan is in private beta. This form builds a structured report with your current settings pre-filled. Copy or email it — nothing is auto-uploaded. You decide what to include.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var phraseBlock: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("What you said & what happened")
                .font(StenoDesign.bodyEmphasis())

            labeledField(
                "App you dictated into (e.g. Terminal, Claude, Notes)",
                text: $appUsed,
                autoFill: frontmostAppLabel
            )
            labeledTextEditor("Phrase you spoke", text: $phraseSaid, height: 60)
            labeledTextEditor("What Lisan transcribed", text: $whatCameOut, height: 60, autoFill: controller.lastTranscript)
            labeledTextEditor("What it should have been (if different)", text: $whatShouldHaveComeOut, height: 60)
        }
    }

    private var contextBlock: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Context")
                .font(StenoDesign.bodyEmphasis())

            Picker("Dialect", selection: $dialect) {
                ForEach(Dialect.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Correction flow outcome", selection: $correctionFixedIt) {
                ForEach(CorrectionOutcome.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            // Auto-captured metadata preview — read-only, always attached.
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-captured settings (included in report)")
                    .font(StenoDesign.captionEmphasis())
                    .foregroundStyle(StenoDesign.textSecondary)
                Text(metadataSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(StenoDesign.textSecondary)
                    .textSelection(.enabled)
                    .padding(StenoDesign.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StenoDesign.surfaceSecondary)
                    .cornerRadius(StenoDesign.radiusSmall)
            }
        }
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: StenoDesign.xs) {
            Text("Extra notes (optional)")
                .font(StenoDesign.bodyEmphasis())
            TextEditor(text: $notes)
                .font(StenoDesign.body())
                .frame(minHeight: 80)
                .padding(StenoDesign.xs)
                .background(StenoDesign.surface)
                .cornerRadius(StenoDesign.radiusSmall)
            Text("Anything a real reviewer would want to know: background noise, mic used, whether this is reproducible, etc.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onDismiss)
                .buttonStyle(.bordered)
            Button("Copy report") { copyReport() }
                .buttonStyle(.bordered)
            Button("Email report") { emailReport() }
                .buttonStyle(.borderedProminent)
                .tint(StenoDesign.accent)
        }
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, autoFill: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(StenoDesign.captionEmphasis())
                .foregroundStyle(StenoDesign.textSecondary)
            HStack {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                if let autoFill, !autoFill.isEmpty, text.wrappedValue.isEmpty {
                    Button("Use \(autoFill)") { text.wrappedValue = autoFill }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func labeledTextEditor(
        _ label: String,
        text: Binding<String>,
        height: CGFloat,
        autoFill: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(StenoDesign.captionEmphasis())
                    .foregroundStyle(StenoDesign.textSecondary)
                Spacer()
                if let autoFill, !autoFill.isEmpty, text.wrappedValue.isEmpty {
                    Button("Use last transcript") { text.wrappedValue = autoFill }
                        .buttonStyle(.plain)
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.accent)
                }
            }
            TextEditor(text: text)
                .font(StenoDesign.body())
                .frame(minHeight: height)
                .padding(StenoDesign.xs)
                .background(StenoDesign.surface)
                .cornerRadius(StenoDesign.radiusSmall)
        }
    }

    // MARK: - Metadata assembly

    private var frontmostAppLabel: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    private var metadataSummary: String {
        let dict = controller.preferences.dictation
        let modelLabel: String = {
            if let entry = WhisperModelCatalog.entry(forModelPath: dict.modelPath) {
                return "\(entry.displayName) (\(entry.sizeLabel))"
            }
            let filename = (dict.modelPath as NSString).lastPathComponent
            return filename.isEmpty ? "custom" : filename
        }()
        let packs = dict.enabledPackFilenames.isEmpty
            ? "(all packs, legacy default)"
            : dict.enabledPackFilenames.joined(separator: ", ")
        let lisanVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return """
        Lisan version: \(lisanVersion)
        Model: \(modelLabel)
        Language mode: \(dict.languageMode.displayName)
        Two-pass auto-detect: \(dict.twoPassAutoDetect ? "on" : "off")
        Segmented auto-detect: \(dict.segmentedAutoDetect ? "on" : "off")
        VAD: \(dict.vadEnabled ? "on" : "off")
        Bilingual cleanup: \(dict.bilingualCleanupEnabled ? "on" : "off")
        Packs enabled: \(packs)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }

    private func composedReport() -> String {
        """
        === Lisan beta feedback ===

        App dictated into: \(appUsed.isEmpty ? "(not specified)" : appUsed)
        Dialect: \(dialect.rawValue)
        Correction outcome: \(correctionFixedIt.rawValue)

        --- Phrase you spoke ---
        \(phraseSaid.isEmpty ? "(not provided)" : phraseSaid)

        --- What Lisan transcribed ---
        \(whatCameOut.isEmpty ? "(not provided)" : whatCameOut)

        --- What it should have been ---
        \(whatShouldHaveComeOut.isEmpty ? "(same / not provided)" : whatShouldHaveComeOut)

        --- Notes ---
        \(notes.isEmpty ? "(none)" : notes)

        --- Auto-captured settings ---
        \(metadataSummary)
        """
    }

    // MARK: - Actions

    private func copyReport() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(composedReport(), forType: .string)
        submitConfirmation = "Report copied to clipboard."
    }

    private func emailReport() {
        let subject = "Lisan beta feedback: \(appUsed.isEmpty ? "general" : appUsed)"
        let body = composedReport()
        let allowed = CharacterSet.urlQueryAllowed
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let mailto = "mailto:beta@lisanapp.io?subject=\(subjectEncoded)&body=\(bodyEncoded)"
        if let url = URL(string: mailto) {
            NSWorkspace.shared.open(url)
            submitConfirmation = "Opened in your email client."
        }
    }
}
