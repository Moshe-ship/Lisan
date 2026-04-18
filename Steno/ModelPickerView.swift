import SwiftUI
import StenoKit

/// Lets users pick from a curated list of whisper.cpp multilingual models
/// and download them on demand. Works on a plain Binding<String> so it
/// can be hosted both in Settings (against AppPreferences) and in
/// Onboarding (against a local @State path).
struct ModelPickerView: View {
    @Binding var modelPath: String
    @State private var downloading: Set<String> = []
    @State private var progressByID: [String: Double] = [:]
    @State private var errorMessage: String?

    private let downloader = WhisperModelDownloader()

    private var modelsDirectory: URL {
        let parent = (modelPath as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            return URL(fileURLWithPath: parent, isDirectory: true)
        }
        // Fall back to the conventional whisper.cpp vendor location.
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("vendor/whisper.cpp/models", isDirectory: true)
    }

    private var activeFilename: String {
        (modelPath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StenoDesign.sm) {
            Text("Model")
                .font(StenoDesign.bodyEmphasis())

            Text("Larger models transcribe Arabic more reliably. The base model misidentifies short Arabic utterances as English — upgrade to Small for real bilingual use.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(WhisperModelCatalog.entries) { entry in
                modelRow(entry)
            }

            if let errorMessage {
                HStack(spacing: StenoDesign.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(StenoDesign.error)
                    Text(errorMessage)
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.error)
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ entry: WhisperModelCatalog.Entry) -> some View {
        let isInstalled = WhisperModelCatalog.isInstalled(entry: entry, in: modelsDirectory)
        let isActive = activeFilename == entry.filename
        let isDownloading = downloading.contains(entry.id)
        let progress = progressByID[entry.id] ?? 0

        HStack(alignment: .top, spacing: StenoDesign.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: StenoDesign.xs) {
                    Text(entry.displayName)
                        .font(StenoDesign.body())
                    Text("· \(entry.sizeLabel)")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                    if isActive {
                        Text("Active")
                            .font(StenoDesign.caption())
                            .foregroundStyle(StenoDesign.accent)
                            .padding(.horizontal, StenoDesign.xs)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(StenoDesign.accent, lineWidth: 1)
                            )
                    }
                }
                Text(entry.summary)
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isDownloading {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(StenoDesign.accent)
                        .padding(.top, 2)
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.textSecondary)
                }
            }

            Spacer()

            actionButton(for: entry, isInstalled: isInstalled, isActive: isActive, isDownloading: isDownloading)
        }
        .padding(.vertical, StenoDesign.xs)
    }

    @ViewBuilder
    private func actionButton(
        for entry: WhisperModelCatalog.Entry,
        isInstalled: Bool,
        isActive: Bool,
        isDownloading: Bool
    ) -> some View {
        if isDownloading {
            Button("Cancel") {
                Task { await downloader.cancel() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if isActive {
            Text("In use")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
        } else if isInstalled {
            Button("Use") {
                use(entry)
            }
            .buttonStyle(.borderedProminent)
            .tint(StenoDesign.accent)
            .controlSize(.small)
        } else {
            Button("Download") {
                download(entry)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func use(_ entry: WhisperModelCatalog.Entry) {
        let newPath = modelsDirectory.appendingPathComponent(entry.filename).path
        modelPath = newPath
        errorMessage = nil
    }

    private func download(_ entry: WhisperModelCatalog.Entry) {
        downloading.insert(entry.id)
        progressByID[entry.id] = 0
        errorMessage = nil

        Task {
            do {
                let finalURL = try await downloader.download(
                    entry: entry,
                    into: modelsDirectory
                ) { progress in
                    Task { @MainActor in
                        progressByID[entry.id] = progress.fraction
                    }
                }
                await MainActor.run {
                    downloading.remove(entry.id)
                    progressByID[entry.id] = 1.0
                    modelPath = finalURL.path
                }
            } catch {
                await MainActor.run {
                    downloading.remove(entry.id)
                    progressByID[entry.id] = 0
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
