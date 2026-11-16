import Foundation
import AVFoundation

public struct ShrinkSettings: Equatable, Sendable {
    public var maxHeight: Int   // short side: 1080 or 720
    public var maxFPS: Int      // 60 or 30
    public var archiveFolder: URL?   // save the full-quality original here first

    public init(maxHeight: Int, maxFPS: Int, archiveFolder: URL? = nil) {
        self.maxHeight = maxHeight
        self.maxFPS = maxFPS
        self.archiveFolder = archiveFolder
    }

    /// HEVC keeps HDR at 1080p; there's no HEVC 720p preset, so 720p is H.264 (SDR).
    public var preset: String {
        maxHeight >= 1080 ? AVAssetExportPresetHEVC1920x1080 : AVAssetExportPreset1280x720
    }

    public enum Plan: Equatable {
        case shrink(scale: Bool, frameRate: Bool)
        case alreadySmall(shortSide: Int, fps: Int)
    }

    /// What re-encoding would change for a video of this (oriented) size and frame rate.
    public func plan(width: Int, height: Int, fps: Float) -> Plan {
        let shortSide = min(width, height)
        let scale = shortSide > maxHeight
        let frameRate = fps > Float(maxFPS) + 1   // 60.13 fps counts as 60
        return scale || frameRate ? .shrink(scale: scale, frameRate: frameRate)
                                  : .alreadySmall(shortSide: shortSide, fps: Int(fps.rounded()))
    }

    /// A copy replaces the original only if it's at least 10% smaller.
    public static func worthReplacing(original: Int64, copy: Int64) -> Bool {
        copy > 0 && copy < original * 9 / 10
    }
}
