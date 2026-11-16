// The preview pane, thumbnails and the AppKit player view.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

struct Thumb: View {
    let asset: PHAsset
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
        }
        .frame(width: 68, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: asset.localIdentifier) { image = await Media.image(asset, side: 140) }
    }
}

/// AppKit player view. Used instead of SwiftUI's `VideoPlayer`, whose
/// `_AVKit_SwiftUI` wrapper aborts during metadata setup on this macOS.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = true
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) {
        v.player?.pause()
        v.player = nil
    }
}

struct DetailView: View {
    let item: VideoItem?
    let selectedCount: Int
    let selectedBytes: Int64
    @State private var poster: NSImage?
    @State private var player: AVPlayer?
    @State private var downloading: Double?
    @State private var fps: Float?

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        preview(item)
                        info(item)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text(selectedCount > 1 ? "\(selectedCount) videos selected · \(fmtBytes(selectedBytes))" : "Select a video to preview it")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item?.id) {
            player?.pause()
            player = nil
            downloading = nil
            poster = nil
            fps = nil
            if let item {
                poster = await Media.image(item.asset, side: 900)
                fps = await Media.frameRate(item.asset)
            }
        }
    }

    func preview(_ item: VideoItem) -> some View {
        ZStack {
            Color.black
            if let player {
                PlayerView(player: player)
            } else {
                if let poster { Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit) }
                if let downloading {
                    VStack {
                        ProgressView(value: downloading).frame(width: 160)
                        Text("Fetching from iCloud…").font(.caption).foregroundStyle(.white)
                    }
                    .padding(10).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Button { play(item) } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 54))
                            .foregroundStyle(.white.opacity(0.9)).shadow(radius: 6)
                    }
                    .buttonStyle(.plain)
                    .help("Play (may download from iCloud if not stored on this Mac)")
                }
            }
        }
        .aspectRatio(CGFloat(max(item.width, 1)) / CGFloat(max(item.height, 1)), contentMode: .fit)
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func play(_ item: VideoItem) {
        downloading = 0
        let id = item.id
        Task {
            let playerItem = await Media.playerItem(item.asset) { p in
                Task { @MainActor in if downloading != nil { downloading = p } }
            }
            guard self.item?.id == id else { return }
            downloading = nil
            if let playerItem {
                let p = AVPlayer(playerItem: playerItem)
                player = p
                p.play()
            }
        }
    }

    func info(_ item: VideoItem) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Size", fmtBytes(item.bytes))
            if item.isEdited { row("Edited", "Yes — moving saves the original and an edited copy") }
            row("Length", fmtDur(item.duration))
            row("Rate", String(format: "%.0f MB per minute", item.mbPerMin))
            row("Resolution", "\(item.width) × \(item.height)")
            row("Frame rate", fps.map { String(format: "%.0f fps", $0) } ?? "— (not downloaded to this Mac)")
            row("Date", item.sortDate.formatted(date: .long, time: .shortened))
            row("File", item.filename)
        }
        .textSelection(.enabled)
    }

    func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v)
        }
    }
}
