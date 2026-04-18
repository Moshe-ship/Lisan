import SwiftUI
import StenoKit

/// Settings → Diagnostics: shows recent `DiagnosticEvent`s with a
/// human-readable summary, copy-for-support button, and clear-all.
///
/// The rendering logic depends on `DiagnosticEvent` being a closed sum
/// type — every case is handled explicitly so new categories surface
/// as compile errors instead of "unknown" fallbacks.
struct DiagnosticsSettingsSection: View {
    @State private var records: [DiagnosticRecord] = []
    @State private var isLoading = false
    @State private var copyFeedback: String? = nil

    private let telemetry: DiagnosticsTelemetry

    init(telemetry: DiagnosticsTelemetry) {
        self.telemetry = telemetry
    }

    var body: some View {
        settingsCard("Diagnostics") {
            VStack(alignment: .leading, spacing: StenoDesign.sm) {
                Text("Recent local events — no voice, no transcript, no content.")
                    .font(StenoDesign.caption())
                    .foregroundStyle(StenoDesign.textSecondary)

                if records.isEmpty {
                    emptyState
                } else {
                    ForEach(records, id: \.timestamp) { row(for: $0) }
                }

                Divider().padding(.vertical, StenoDesign.xs)

                HStack(spacing: StenoDesign.sm) {
                    Button("Refresh") {
                        Task { await reload() }
                    }
                    Button("Copy for support") {
                        Task { await copyToClipboard() }
                    }
                    .disabled(records.isEmpty)
                    Spacer()
                    Button("Clear all", role: .destructive) {
                        Task {
                            try? await telemetry.clear()
                            await reload()
                        }
                    }
                    .disabled(records.isEmpty)
                }

                if let msg = copyFeedback {
                    Text(msg)
                        .font(StenoDesign.caption())
                        .foregroundStyle(StenoDesign.success)
                }
            }
        }
        .task { await reload() }
    }

    // MARK: - Rows

    private var emptyState: some View {
        HStack(spacing: StenoDesign.xs) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(StenoDesign.success)
            Text("No diagnostic events recorded.")
                .font(StenoDesign.caption())
                .foregroundStyle(StenoDesign.textSecondary)
        }
        .padding(.vertical, StenoDesign.xs)
    }

    @ViewBuilder
    private func row(for record: DiagnosticRecord) -> some View {
        HStack(alignment: .top, spacing: StenoDesign.sm) {
            Image(systemName: icon(for: record.event))
                .font(StenoDesign.caption())
                .foregroundStyle(color(for: record.event))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary(for: record.event))
                    .font(StenoDesign.caption())
                Text(relative(record.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StenoDesign.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, StenoDesign.xxs)
    }

    // MARK: - Event rendering

    private func summary(for event: DiagnosticEvent) -> String {
        switch event {
        case .startupFailure(let phase, let code):
            return "Startup failed in \(phase.rawValue) (\(code.rawValue))"
        case .insertionFailure(let method, let bundle, let reason):
            let where_ = bundle?.value ?? "unknown app"
            return "Insertion via \(method.rawValue) to \(where_) failed: \(reason.rawValue)"
        case .modelNotFound(let kind, let path):
            return "\(kind.rawValue.capitalized) model not found at \(path.redacted)"
        case .engineError(let process, let exitCode):
            return "\(process.rawValue) exited with code \(exitCode)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission.rawValue)"
        case .configValidationFailure(let field, let reason):
            return "Config field \(field.rawValue) rejected: \(reason.rawValue)"
        case .notarizationMismatch:
            return "Notarization ticket is missing or invalid"
        }
    }

    private func icon(for event: DiagnosticEvent) -> String {
        switch event {
        case .startupFailure:             return "bolt.slash"
        case .insertionFailure:           return "keyboard.badge.ellipsis"
        case .modelNotFound:              return "doc.questionmark"
        case .engineError:                return "exclamationmark.triangle"
        case .permissionDenied:           return "lock.slash"
        case .configValidationFailure:    return "gearshape.badge.xmark"
        case .notarizationMismatch:       return "seal.slash"
        }
    }

    private func color(for event: DiagnosticEvent) -> Color {
        switch event {
        case .startupFailure, .engineError, .notarizationMismatch:
            return StenoDesign.error
        case .insertionFailure, .modelNotFound, .configValidationFailure:
            return StenoDesign.warning
        case .permissionDenied:
            return StenoDesign.accent
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        records = await telemetry.recent()
    }

    private func copyToClipboard() async {
        let items = await telemetry.recent()
        let lines = items.map { r -> String in
            let ts = ISO8601DateFormatter().string(from: r.timestamp)
            return "\(ts)  \(summary(for: r.event))"
        }
        let text = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copyFeedback = "Copied \(items.count) events to clipboard."
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        copyFeedback = nil
    }
}
