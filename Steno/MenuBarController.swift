import AppKit
import StenoKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var controller: DictationController?

    func setup(controller: DictationController) {
        self.controller = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "mic.circle",
                accessibilityDescription: "Lisan"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    func updateIcon(isRecording: Bool, handsFreeOn: Bool) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if isRecording {
            symbolName = "waveform.circle.fill"
        } else if handsFreeOn {
            symbolName = "mic.circle.fill"
        } else {
            symbolName = "mic.circle"
        }

        let description = isRecording ? "Lisan recording" : (handsFreeOn ? "Lisan hands-free" : "Lisan")
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )
        button.image?.isTemplate = true
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.windows.first { $0.isKeyWindow || $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }

    private func showMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Lisan", action: #selector(showWindowAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        // Read-only status rows so users can glance at what's loaded
        // without opening the window.
        if let modelLabel = modelStatusLabel() {
            let item = NSMenuItem(title: modelLabel, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let languageLabel = languageStatusLabel() {
            let item = NSMenuItem(title: languageLabel, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let handsFreeTitle = controller?.handsFreeOn == true ? "Stop Hands-Free" : "Start Hands-Free"
        let handsFreeItem = NSMenuItem(title: handsFreeTitle, action: #selector(toggleHandsFreeAction), keyEquivalent: "")
        handsFreeItem.target = self
        menu.addItem(handsFreeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Lisan", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showWindowAction() {
        showWindow()
    }

    @objc private func toggleHandsFreeAction() {
        controller?.toggleHandsFree()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func modelStatusLabel() -> String? {
        guard let path = controller?.preferences.dictation.modelPath,
              !path.isEmpty else {
            return nil
        }
        if let entry = WhisperModelCatalog.entry(forModelPath: path) {
            return "Model: \(entry.displayName)"
        }
        let filename = (path as NSString).lastPathComponent
        return filename.isEmpty ? nil : "Model: \(filename)"
    }

    private func languageStatusLabel() -> String? {
        guard let mode = controller?.preferences.dictation.languageMode else { return nil }
        return "Language: \(mode.displayName)"
    }
}
