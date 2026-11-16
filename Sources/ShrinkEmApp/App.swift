// ShrinkEm — browse the Photos library's videos sorted by file size.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import ShrinkEmKit

@main
struct ShrinkEmApp: App {
    @StateObject private var lib = Library()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before Library reads the Keep marks and the views read their settings.
        SettingsMigration.run()
    }

    var body: some Scene {
        WindowGroup("ShrinkEm") {
            ContentView()
                .tint(Brand.mintDeep)
                .environmentObject(lib)
                .frame(minWidth: 1150, minHeight: 650)
                .onAppear { appDelegate.library = lib }
        }
    }
}

/// Asks before quitting while jobs are queued or running. Closing the window doesn't
/// stop them: the app keeps working, and the Dock badge counts what's left.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var library: Library?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let queue = library?.queue, queue.isWorking else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "ShrinkEm is still working"
        let n = queue.remainingVideos
        let shrinking = queue.jobs.contains { $0.isActive && $0.isShrink }
        alert.informativeText = "\(n) video\(n == 1 ? " is" : "s are") still in the queue. If you quit, the rest are left as they are."
            + (shrinking ? " Videos already shrunk in the current job will have both versions in Photos until you delete the originals." : "")
        alert.addButton(withTitle: "Keep Working")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

/// Brand colours (docs/BRAND.md). In the app, system colours do most of the work;
/// Mint deep is the accent.
enum Brand {
    static let mintDeep = Color(red: 0x1F / 255, green: 0xA5 / 255, blue: 0x88 / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x4A / 255)
}

/// One-time copy of settings from the app's old identity. ShrinkEm shipped as
/// "Slimreel" (bundle ID `ie.duggan.Slimreel`, v1.0.0); macOS treats the new bundle ID
/// as a new app, so its preferences start empty. Photos access can't be carried over:
/// macOS asks again once.
enum SettingsMigration {
    static let oldDomain = "ie.duggan.Slimreel"
    static let doneKey = "migratedFromSlimreel"
    static let keys = ["kept", "minMB", "hideKept", "moveFolder", "shrinkHeight", "shrinkFPS", "shrinkArchive"]

    /// Returns the keys it copied (for the test hook).
    @discardableResult
    static func run(from old: UserDefaults? = UserDefaults(suiteName: oldDomain),
                    to new: UserDefaults = .standard) -> [String] {
        guard !new.bool(forKey: doneKey) else { return [] }
        defer { new.set(true, forKey: doneKey) }
        guard let old else { return [] }
        var copied: [String] = []
        for key in keys where new.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                new.set(value, forKey: key)
                copied.append(key)
            }
        }
        return copied
    }
}
