import Foundation
import OSLog

enum StenoKitDiagnostics {
    // StenoKit uses its own subsystem so package logs can be filtered separately
    // from app-layer logs (which use io.stenoapp.steno).
    static let logger = Logger(subsystem: "io.stenoapp.stenokit", category: "Diagnostics")
}
