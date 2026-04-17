import Foundation
import OSLog

enum StenoKitDiagnostics {
    // StenoKit uses its own subsystem so package logs can be filtered separately
    // from app-layer logs (which use io.lisanapp.lisan).
    static let logger = Logger(subsystem: "io.lisanapp.stenokit", category: "Diagnostics")
}
