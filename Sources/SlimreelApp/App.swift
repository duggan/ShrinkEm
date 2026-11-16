// Slimreel — browse the Photos library's videos sorted by file size.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

@main
struct SlimreelApp: App {
    @StateObject private var lib = Library()
    var body: some Scene {
        WindowGroup("Slimreel") {
            ContentView()
                .tint(Brand.mintDeep)
                .environmentObject(lib)
                .frame(minWidth: 1150, minHeight: 650)
        }
    }
}

/// Brand colours (docs/BRAND.md). In the app, system colours do most of the work;
/// Mint deep is the accent.
enum Brand {
    static let mintDeep = Color(red: 0x1F / 255, green: 0xA5 / 255, blue: 0x88 / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x4A / 255)
}
