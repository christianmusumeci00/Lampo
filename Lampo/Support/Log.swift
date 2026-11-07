import os

/// Centralised loggers. Never log user content (prompts, selections, responses):
/// log sizes, states and error kinds only.
enum Log {
    static let subsystem = "app.lampo.Lampo"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let context = Logger(subsystem: subsystem, category: "context")
    static let output = Logger(subsystem: subsystem, category: "output")
}
