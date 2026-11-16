// Thumbnails, frame rates and playback items from Photos.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

enum Media {
    static let manager = PHCachingImageManager()

    static func image(_ asset: PHAsset, side: CGFloat) async -> NSImage? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat   // handler fires exactly once
            o.resizeMode = .fast
            o.isNetworkAccessAllowed = true
            manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                 contentMode: .aspectFill, options: o) { img, _ in
                cont.resume(returning: img)
            }
        }
    }

    /// Frame rate if the video is on this Mac (doesn't download from iCloud).
    static func frameRate(_ asset: PHAsset) async -> Float? {
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = false
        o.version = .original
        let av: AVAsset? = await withCheckedContinuation { c in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: o) { a, _, _ in c.resume(returning: a) }
        }
        guard let track = try? await av?.loadTracks(withMediaType: .video).first else { return nil }
        return try? await track.load(.nominalFrameRate)
    }

    static func playerItem(_ asset: PHAsset, progress: @escaping @Sendable (Double) -> Void) async -> AVPlayerItem? {
        await withCheckedContinuation { cont in
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .automatic
            o.progressHandler = { p, _, _, _ in progress(p) }
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: o) { item, _ in
                cont.resume(returning: item)
            }
        }
    }
}
