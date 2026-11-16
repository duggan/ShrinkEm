// Slimreel — browse the Photos library's videos sorted by file size.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

@main
struct SlimreelApp: App {
    @StateObject private var lib = Library()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Slimreel") {
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
        alert.messageText = "Slimreel is still working"
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
